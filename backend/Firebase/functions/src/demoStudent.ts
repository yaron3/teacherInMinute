import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onValueCreated } from "firebase-functions/v2/database";
import { getRemoteConfig } from "firebase-admin/remote-config";
import { Timestamp } from "firebase-admin/firestore";
import { v4 as uuidv4 } from "uuid";

import {
  ConversationType,
  CONVERSATION_TYPES,
  DEFAULT_CONVERSATION_TYPE,
  CONNECTION_FEE_CENTS,
  INVITE_EXPIRY_SECONDS,
  QuestionDoc,
} from "./types";

const db = admin.database();
const firestore = admin.firestore();

// Identity of the simulated student. Must match the demo-student service's
// defaults (DEMO_STUDENT_UID / DEMO_STUDENT_NAME) so both paths look the same.
const DEMO_STUDENT_UID = "demo-student";
const DEMO_STUDENT_NAME = "Demo Student";
const DEMO_STUDENT_MINUTES = 120;

const VALID_TOPICS = ["algebra", "geometry", "trigonometry", "calculus", "statistics", "arithmetic"];
const VALID_DIFFICULTIES = ["easy", "medium", "hard"];

// Remote Config keys holding the canned message used when the local AI is down.
// Follows the app's `<key>_<language>` convention, falling back to the bare key.
const OFFLINE_MESSAGE_KEY = "demo_student_offline_message";
const DEFAULT_OFFLINE_MESSAGE = "This is an automatic message from Demo #{count}";

// Master switch for the whole demo feature. Unset means "allowed" so an
// existing setup keeps working before the flag is published; publish it as
// false to turn simulations off everywhere without shipping an app build.
const FEATURE_FLAG_KEY = "demo_student_enabled";

// Replies stop after this many canned messages in one chat, so a forgotten demo
// session can't loop forever.
const MAX_FALLBACK_REPLIES = 30;

// ─── Remote Config ───────────────────────────────────────────────────────────

interface CachedTemplate {
  parameters: Record<string, unknown>;
  fetchedAt: number;
}

let templateCache: CachedTemplate | null = null;
const TEMPLATE_TTL_MS = 5 * 60 * 1000;

async function remoteConfigParameters(): Promise<Record<string, unknown>> {
  if (templateCache && Date.now() - templateCache.fetchedAt < TEMPLATE_TTL_MS) {
    return templateCache.parameters;
  }
  try {
    const template = await getRemoteConfig().getTemplate();
    templateCache = {
      parameters: template.parameters as unknown as Record<string, unknown>,
      fetchedAt: Date.now(),
    };
    return templateCache.parameters;
  } catch (err) {
    logger.warn(`[demoStudent] could not read Remote Config: ${err instanceof Error ? err.message : String(err)}`);
    return templateCache?.parameters ?? {};
  }
}

function parameterValue(parameters: Record<string, unknown>, key: string): string | null {
  const param = parameters[key] as { defaultValue?: { value?: string } } | undefined;
  const value = param?.defaultValue?.value;
  return typeof value === "string" && value.trim() ? value : null;
}

/**
 * The canned message template for `language`, with `{count}` still in place.
 * Looks up `<key>_<language>` first (the app's convention), then the bare key,
 * then a built-in default so a demo never comes up empty.
 */
async function offlineMessageTemplate(language: string): Promise<string> {
  const parameters = await remoteConfigParameters();
  return (
    parameterValue(parameters, `${OFFLINE_MESSAGE_KEY}_${language}`) ??
    parameterValue(parameters, OFFLINE_MESSAGE_KEY) ??
    DEFAULT_OFFLINE_MESSAGE
  );
}

/**
 * Whether simulations are allowed at all. Reads the same `demo_student_enabled`
 * flag the app uses to show the button, so one switch covers both. Note the
 * Remote Config template is cached for a few minutes — flipping the flag takes
 * up to TEMPLATE_TTL_MS to take effect here.
 */
async function isFeatureEnabled(): Promise<boolean> {
  const parameters = await remoteConfigParameters();
  const raw = parameterValue(parameters, FEATURE_FLAG_KEY);
  if (raw === null) return true; // never published — don't break a working setup
  return !["false", "0", "no", "off"].includes(raw.trim().toLowerCase());
}

/** Fills the counter into the template. Appends `#N` when it has no placeholder. */
function renderOfflineMessage(template: string, count: number): string {
  if (/\{count\}/i.test(template)) return template.replace(/\{count\}/gi, String(count));
  if (/%d/.test(template)) return template.replace(/%d/, String(count));
  return `${template.trimEnd()} #${count}`;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

async function isLocalServiceOnline(): Promise<boolean> {
  try {
    const snap = await db.ref("demoStudent/service/status").once("value");
    return snap.val() === "online";
  } catch (err) {
    logger.warn(`[demoStudent] presence read failed: ${err instanceof Error ? err.message : String(err)}`);
    return false;
  }
}

/** Keeps the simulated student funded so a demo lesson never stops on billing. */
async function ensureDemoStudentProfile(): Promise<void> {
  const ref = firestore.collection("users").doc(DEMO_STUDENT_UID);
  const snap = await ref.get();
  const data = snap.data() ?? {};
  const patch: Record<string, unknown> = {
    fullName: DEMO_STUDENT_NAME,
    role: "student",
    isDemo: true,
  };
  if (((data.remainingMinutes as number | undefined) ?? 0) < DEMO_STUDENT_MINUTES) {
    patch.remainingMinutes = DEMO_STUDENT_MINUTES;
  }
  if (data.totalMinutes === undefined) patch.totalMinutes = 0;
  await ref.set(patch, { merge: true });
}

/**
 * Creates a simulated question and invites only the teacher who asked for it.
 * Mirrors what the demo-student service does locally, so both paths produce the
 * same shape — `dispatchQuestion` skips fan-out for anything flagged isDemo.
 */
async function createFallbackQuestion(params: {
  teacherUid: string;
  topic: string;
  conversationType: ConversationType;
  language: string;
  text: string;
}): Promise<string> {
  const qid = uuidv4();
  const now = Date.now();

  await db.ref(`questions/${qid}`).update({
    questionId: qid,
    studentUid: DEMO_STUDENT_UID,
    studentId: DEMO_STUDENT_UID,
    studentName: DEMO_STUDENT_NAME,
    studentImageURL: "",
    topic: params.topic,
    text: params.text,
    conversationType: params.conversationType,
    status: "searching",
    dispatchWave: 1,
    isDemo: true,
    demoFallback: true,
    demoTeacherUid: params.teacherUid,
    demoMessageCount: 1,
    // Kept on the node so auto-replies answer in the language the teacher asked in.
    language: params.language,
    createdAt: now,
    updatedAt: now,
  });

  await firestore.collection("questions").doc(qid).set({
    studentUid: DEMO_STUDENT_UID,
    studentName: DEMO_STUDENT_NAME,
    studentImageURL: "",
    topic: params.topic,
    text: params.text,
    photoUrls: [],
    conversationType: params.conversationType,
    status: "searching",
    createdAt: Timestamp.fromMillis(now),
    updatedAt: Timestamp.fromMillis(now),
    dispatchWave: 1,
    alreadyInvited: [params.teacherUid],
    isDemo: true,
    demoFallback: true,
    demoTeacherUid: params.teacherUid,
  });

  const expiresAt = now + INVITE_EXPIRY_SECONDS * 1000;

  await firestore
    .collection("questions")
    .doc(qid)
    .collection("invites")
    .doc(params.teacherUid)
    .set({
      teacherUid: params.teacherUid,
      questionId: qid,
      sentAt: Timestamp.fromMillis(now),
      expiresAt: Timestamp.fromMillis(expiresAt),
      response: "pending",
      wave: 1,
      conversationType: params.conversationType,
    });

  await db.ref(`teacherInvites/${params.teacherUid}/${qid}`).set({
    topic: params.topic,
    text: params.text.slice(0, 300),
    photoUrls: [],
    studentId: DEMO_STUDENT_UID,
    studentName: DEMO_STUDENT_NAME,
    studentImageURL: "",
    expiresAt,
    wave: 1,
    conversationType: params.conversationType,
    connectionFeeCents: CONNECTION_FEE_CENTS,
    isDemo: true,
  });

  return qid;
}

// ─── simulateDemoQuestion — callable ─────────────────────────────────────────
// The teacher app asks for a simulated question here rather than writing to
// RTDB itself, so the decision of *who* answers is made server-side: the local
// Qwen service when it is up, canned Remote Config messages when it is not.

export const simulateDemoQuestion = onCall(async (req) => {
  const teacherUid = req.auth?.uid;
  if (!teacherUid) throw new HttpsError("unauthenticated", "Sign in required");

  if (!(await isFeatureEnabled())) {
    logger.info(`[demoStudent] simulate refused teacher=${teacherUid} — ${FEATURE_FLAG_KEY} is off`);
    throw new HttpsError("failed-precondition", "The demo question feature is turned off.");
  }

  const {
    topic: rawTopic,
    difficulty: rawDifficulty,
    conversationType: rawConversationType,
    language: rawLanguage,
    hint: rawHint,
    teacherName,
  } = req.data as {
    topic?: string;
    difficulty?: string;
    conversationType?: string;
    language?: string;
    hint?: string;
    teacherName?: string;
  };

  const topic = VALID_TOPICS.includes(String(rawTopic)) ? String(rawTopic) : "algebra";
  const difficulty = VALID_DIFFICULTIES.includes(String(rawDifficulty))
    ? String(rawDifficulty)
    : "medium";
  const conversationType: ConversationType = CONVERSATION_TYPES.includes(
    rawConversationType as ConversationType
  )
    ? (rawConversationType as ConversationType)
    : DEFAULT_CONVERSATION_TYPE;
  const language = String(rawLanguage ?? "en").toLowerCase() === "he" ? "he" : "en";
  const hint = String(rawHint ?? "").trim().slice(0, 200);

  await ensureDemoStudentProfile();

  const localOnline = await isLocalServiceOnline();
  logger.info(
    `[demoStudent] simulate requested teacher=${teacherUid} topic=${topic} localService=${localOnline ? "online" : "offline"}`
  );

  if (localOnline) {
    // Hand it to the laptop: it writes the question with the local model.
    const requestRef = db.ref("demoStudent/requests").push();
    await requestRef.set({
      teacherUid,
      teacherName: String(teacherName ?? ""),
      topic,
      difficulty,
      conversationType,
      language,
      hint,
      status: "pending",
      createdAt: Date.now(),
    });
    return { mode: "local", requestId: requestRef.key };
  }

  // No local model available — use the canned message, numbered from 1.
  const template = await offlineMessageTemplate(language);
  const text = renderOfflineMessage(template, 1);
  const questionId = await createFallbackQuestion({
    teacherUid,
    topic,
    conversationType,
    language,
    text,
  });

  logger.info(`[demoStudent] fallback question created qid=${questionId} teacher=${teacherUid}`);
  return { mode: "fallback", questionId, questionText: text };
});

// ─── demoStudentAutoReply — RTDB trigger ─────────────────────────────────────
// Answers the teacher during a fallback demo, so the chat behaves like someone
// is on the other end even with the laptop service off. Questions handled by
// the local service are left alone — it does the replying there.

export const demoStudentAutoReply = onValueCreated(
  "/questions/{qid}/messages/{mid}",
  async (event) => {
    const qid = event.params.qid;
    const message = event.data.val() as Record<string, unknown> | null;
    if (!message) return;

    if (String(message.senderRole ?? "") !== "teacher") return;
    if (!String(message.text ?? "").trim()) return;

    // Turning the feature off stops canned replies too, mid-session included.
    if (!(await isFeatureEnabled())) return;

    const questionSnap = await db.ref(`questions/${qid}`).once("value");
    if (!questionSnap.exists()) return;

    const question = questionSnap.val() as Record<string, unknown>;
    if (question.isDemo !== true || question.demoFallback !== true) return;

    const status = String(question.status ?? "").toLowerCase();
    if (["completed", "cancelled", "canceled", "expired", "ended"].includes(status)) return;

    // Counter runs across the whole demo: the question was #1, replies follow.
    const counterRef = db.ref(`questions/${qid}/demoMessageCount`);
    const result = await counterRef.transaction((current) => (typeof current === "number" ? current : 1) + 1);
    const count = (result.snapshot.val() as number | null) ?? 2;

    if (count > MAX_FALLBACK_REPLIES) {
      logger.info(`[demoStudent] fallback reply budget reached qid=${qid}`);
      return;
    }

    const language = String(question.language ?? "en") === "he" ? "he" : "en";
    const template = await offlineMessageTemplate(language);
    const text = renderOfflineMessage(template, count);

    await db.ref(`questions/${qid}/messages`).push({
      text,
      senderUid: DEMO_STUDENT_UID,
      senderRole: "student",
      createdAt: Date.now(),
      kind: "text",
    });

    logger.info(`[demoStudent] fallback reply sent qid=${qid} count=${count}`);
  }
);

// Re-exported for tests and for callers that need the question shape.
export type { QuestionDoc };
