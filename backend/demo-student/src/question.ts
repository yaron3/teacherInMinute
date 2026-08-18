import * as admin from "firebase-admin";
import { randomUUID } from "crypto";

import type { Config } from "./config";
import type { Difficulty, Topic } from "./llm";
import { generateQuestion } from "./llm";

// Mirrors functions/src/types.ts — kept local so this service stays standalone.
const INVITE_EXPIRY_SECONDS = 90;
const CONNECTION_FEE_CENTS = 50;

export interface SimulationRequest {
  requestId: string;
  teacherUid: string;
  topic: Topic;
  difficulty: Difficulty;
  language: string;
  conversationType: "text" | "audio" | "video";
  hint?: string;
}

export interface CreatedQuestion {
  questionId: string;
  text: string;
  /** "llm" when the local model wrote the question, "fallback" when it could not. */
  source: "llm" | "fallback";
}

// Used only when the local model is unreachable and fallbacks are allowed, so a
// demo can still be shown without Ollama running.
const FALLBACK_QUESTIONS: Record<Topic, string> = {
  algebra: "I need to solve 3(x - 4) + 5 = 2x + 7 but I keep getting a different answer every time. Where am I going wrong?",
  geometry: "A triangle has sides 7 cm, 24 cm and 25 cm. How do I prove it is right-angled, and how do I find its area?",
  trigonometry: "I have to find all solutions of 2sin(x) = 1 between 0 and 360 degrees. I found 30 degrees, is that the only one?",
  calculus: "How do I find the derivative of f(x) = x^2 * ln(x)? I think I need the product rule but I get stuck halfway.",
  statistics: "My data set is 4, 8, 9, 9, 12, 15. I got the mean but I do not understand how to compute the standard deviation.",
  arithmetic: "A jacket costs 240 and is on sale for 25% off, then another 10% off at the register. What is the final price?",
};

function fallbackQuestion(topic: Topic): string {
  return FALLBACK_QUESTIONS[topic] ?? FALLBACK_QUESTIONS.algebra;
}

/**
 * Makes sure the demo student has a Firestore user doc with enough minutes for
 * a lesson — createQuestion rejects students under 2 remaining minutes, and
 * endLesson bills against this same doc.
 */
export async function ensureDemoStudentProfile(config: Config): Promise<void> {
  const ref = admin.firestore().collection("users").doc(config.studentUid);
  const snap = await ref.get();
  const data = snap.data() ?? {};
  const remainingMinutes = (data.remainingMinutes as number | undefined) ?? 0;

  const patch: Record<string, unknown> = {
    fullName: config.studentName,
    role: "student",
    isDemo: true,
    currency: config.studentCurrency,
    ...(config.studentImageUrl ? { profileImageURL: config.studentImageUrl } : {}),
  };

  // Top up only when the balance ran low, so a demo never stalls on "not enough time".
  if (remainingMinutes < config.studentMinutes) {
    patch.remainingMinutes = config.studentMinutes;
  }
  if (data.totalMinutes === undefined) {
    patch.totalMinutes = 0;
  }

  await ref.set(patch, { merge: true });
  console.log(
    `[demo-student] profile ready uid=${config.studentUid} minutes=${patch.remainingMinutes ?? remainingMinutes}`,
  );
}

/**
 * Creates the simulated question the same way `createQuestion` does — RTDB node
 * first (that is what the teacher app and ai-teacher watch), then the Firestore
 * doc — and marks it as a demo so the real dispatcher leaves it alone.
 */
export async function createDemoQuestion(
  config: Config,
  request: SimulationRequest,
): Promise<CreatedQuestion> {
  let text: string;
  let source: CreatedQuestion["source"] = "llm";

  try {
    text = await generateQuestion(config, {
      topic: request.topic,
      difficulty: request.difficulty,
      language: request.language,
      hint: request.hint,
    });
    console.log(`[demo-student] question generated topic=${request.topic} chars=${text.length}`);
  } catch (err) {
    if (!config.allowFallbackQuestion) throw err;
    text = fallbackQuestion(request.topic);
    source = "fallback";
    console.warn(
      `[demo-student] LLM unavailable (${err instanceof Error ? err.message : String(err)}) — using canned question`,
    );
  }

  const qid = randomUUID();
  const now = Date.now();
  const db = admin.database();
  const firestore = admin.firestore();

  const liveQuestion: Record<string, unknown> = {
    questionId: qid,
    studentUid: config.studentUid,
    studentId: config.studentUid,
    studentName: config.studentName,
    studentImageURL: config.studentImageUrl,
    topic: request.topic,
    text,
    photoUrls: [],
    conversationType: request.conversationType,
    status: "searching",
    dispatchWave: 1,
    isDemo: true,
    demoTeacherUid: request.teacherUid,
    createdAt: now,
    updatedAt: now,
  };

  await db.ref(`questions/${qid}`).update(liveQuestion);

  await firestore.collection("questions").doc(qid).set({
    studentUid: config.studentUid,
    studentName: config.studentName,
    studentImageURL: config.studentImageUrl,
    topic: request.topic,
    text,
    photoUrls: [],
    conversationType: request.conversationType,
    status: "searching",
    createdAt: admin.firestore.Timestamp.fromMillis(now),
    updatedAt: admin.firestore.Timestamp.fromMillis(now),
    dispatchWave: 1,
    alreadyInvited: [request.teacherUid],
    isDemo: true,
    demoTeacherUid: request.teacherUid,
  });

  console.log(`[demo-student] question created qid=${qid} topic=${request.topic} source=${source}`);

  await inviteTeacher(config, qid, request, text);

  return { questionId: qid, text, source };
}

/**
 * Invites exactly one teacher: the one who pressed "simulate". The normal
 * dispatch waves are skipped for demo questions, so this is the only invite.
 */
async function inviteTeacher(
  config: Config,
  qid: string,
  request: SimulationRequest,
  text: string,
): Promise<void> {
  const now = Date.now();
  const expiresAt = now + INVITE_EXPIRY_SECONDS * 1000;

  await admin
    .firestore()
    .collection("questions")
    .doc(qid)
    .collection("invites")
    .doc(request.teacherUid)
    .set({
      teacherUid: request.teacherUid,
      questionId: qid,
      sentAt: admin.firestore.Timestamp.fromMillis(now),
      expiresAt: admin.firestore.Timestamp.fromMillis(expiresAt),
      response: "pending",
      wave: 1,
      conversationType: request.conversationType,
    });

  await admin.database().ref(`teacherInvites/${request.teacherUid}/${qid}`).set({
    topic: request.topic,
    text: text.slice(0, 300),
    photoUrls: [],
    studentId: config.studentUid,
    studentName: config.studentName,
    studentImageURL: config.studentImageUrl,
    expiresAt,
    wave: 1,
    conversationType: request.conversationType,
    connectionFeeCents: CONNECTION_FEE_CENTS,
    isDemo: true,
  });

  console.log(`[demo-student] invite sent qid=${qid} teacher=${request.teacherUid}`);
}
