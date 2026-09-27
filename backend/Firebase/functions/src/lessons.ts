import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { onValueWritten } from "firebase-functions/v2/database";
import { getFunctions } from "firebase-admin/functions";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { v4 as uuidv4 } from "uuid";

import {
  QuestionDoc,
  LessonDoc,
  HARD_CAP_MINUTES,
  ABANDONED_LESSON_GRACE_SECONDS,
  UNSTARTED_LESSON_TIMEOUT_SECONDS,
  LESSON_RECONNECT_GRACE_SECONDS,
  LessonRole,
  LessonSidePresence,
  PurchaseDoc,
} from "./types";
import { calculateBilling, billingStartMillis, applyTeacherBonus } from "./billing";
import { backfillPendingQuestionsForTeacher } from "./dispatch";
import { stampAuthoritativeRating } from "./presence";
import { releaseTeacherBusy } from "./busy";
import { getConnectionFeeCents, resolvePricingForStudent } from "./pricing";
import { readTeacherBonus } from "./emailRewards";

const firestore = admin.firestore();
const db = admin.database();

interface TeacherRatingDoc {
  startedAt: Timestamp;
  endedAt: Timestamp;
  studentId: string;
  studentRate: number;
  /** Optional free text the student wrote about the lesson. Shown back to the
   *  teacher without `studentId` (see ./ratings.ts `teacherReviews`), so it is
   *  the only part of a rating a teacher ever reads. */
  studentComment?: string;
}

/** Long enough for a paragraph of feedback, short enough that one rating stays
 *  a small document. Anything longer is truncated rather than rejected — the
 *  student has already finished the lesson and should not lose the rating to a
 *  validation error. */
const MAX_RATING_COMMENT_LENGTH = 500;

/** The comment as it should be stored: trimmed, capped, and `undefined` when
 *  the student left the box empty. */
function normalizedComment(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (trimmed.length === 0) return undefined;
  return trimmed.slice(0, MAX_RATING_COMMENT_LENGTH);
}

interface TeacherAggregateDoc {
  averageRate?: number;
  /** Denormalised size of the `ratings` subcollection, so reading a teacher's
   *  review count (see ./ratings.ts) is a single document get. */
  ratingCount?: number;
}

function toTimestamp(value: unknown): Timestamp | undefined {
  if (value instanceof Timestamp) return value;
  if (value instanceof Date) return Timestamp.fromDate(value);
  if (typeof value === "number" && Number.isFinite(value)) {
    return Timestamp.fromMillis(value);
  }
  if (
    typeof value === "object" &&
    value !== null &&
    typeof (value as { toMillis?: unknown }).toMillis === "function"
  ) {
    try {
      const millis = Number((value as { toMillis: () => unknown }).toMillis());
      if (Number.isFinite(millis)) return Timestamp.fromMillis(millis);
    } catch {
      // ignore invalid timestamp-like values
    }
  }
  return undefined;
}

function firstString(...values: unknown[]): string | undefined {
  for (const value of values) {
    if (typeof value === "string" && value.trim().length > 0) {
      return value;
    }
  }
  return undefined;
}

function firstNumber(...values: Array<number | undefined>): number | undefined {
  for (const value of values) {
    if (typeof value === "number" && Number.isFinite(value)) {
      return value;
    }
  }
  return undefined;
}

function toMillis(value: unknown): number | undefined {
  if (typeof value === "number" && Number.isFinite(value)) {
    // Heuristic: treat small epochs as seconds.
    return value < 1e12 ? value * 1000 : value;
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? (parsed < 1e12 ? parsed * 1000 : parsed) : undefined;
  }
  if (!value || typeof value !== "object") return undefined;

  const obj = value as Record<string, unknown> & { toMillis?: () => number };

  if (typeof obj.toMillis === "function") {
    const ms = obj.toMillis();
    return Number.isFinite(ms) ? ms : undefined;
  }

  if (typeof obj.seconds === "number") {
    return obj.seconds * 1000;
  }
  if (typeof obj._seconds === "number") {
    return obj._seconds * 1000;
  }
  if (typeof obj.milliseconds === "number") {
    return obj.milliseconds;
  }
  if (typeof obj.ms === "number") {
    return obj.ms;
  }

  return undefined;
}

interface LessonPricingSnapshot {
  currencyCode: string;
  pricePerMinute: number;
  teacherShare: number;
  exchangeRateToUsd: number;
}

function readStampedPricing(lesson: Partial<LessonDoc> | undefined): LessonPricingSnapshot | undefined {
  if (!lesson) return undefined;
  const currency = typeof lesson.currencyCode === "string" ? lesson.currencyCode.trim().toUpperCase() : "";
  const pricePerMinute = Number(lesson.pricePerMinute);
  const teacherShare = Number(lesson.teacherShare);
  const exchangeRate = Number(lesson.exchangeRateToUsd);
  if (
    currency.length === 3 &&
    Number.isFinite(pricePerMinute) && pricePerMinute > 0 &&
    Number.isFinite(teacherShare) && teacherShare > 0 && teacherShare <= 1 &&
    Number.isFinite(exchangeRate) && exchangeRate > 0
  ) {
    return { currencyCode: currency, pricePerMinute, teacherShare, exchangeRateToUsd: exchangeRate };
  }
  return undefined;
}

async function resolveLessonPricing(
  studentUid: string,
  lesson?: Partial<LessonDoc>
): Promise<LessonPricingSnapshot> {
  const stamped = readStampedPricing(lesson);
  if (stamped) return stamped;
  const resolved = await resolvePricingForStudent(studentUid);
  return {
    currencyCode: resolved.currency,
    pricePerMinute: resolved.pricePerMinute,
    teacherShare: resolved.teacherShare,
    exchangeRateToUsd: resolved.exchangeRateToUsd,
  };
}

async function loadLessonDocByQuestionId(questionId: string): Promise<{
  ref: FirebaseFirestore.DocumentReference;
  data: LessonDoc;
} | undefined> {
  const snap = await firestore
    .collection("lessons")
    .where("questionId", "==", questionId)
    .limit(1)
    .get();
  if (snap.empty) return undefined;
  const doc = snap.docs[0];
  return { ref: doc.ref, data: doc.data() as LessonDoc };
}

function sanitizeForFirestore(value: unknown): unknown {
  if (value === undefined) return null;
  if (Array.isArray(value)) return value.map((v) => sanitizeForFirestore(v));
  if (value && typeof value === "object") {
    const input = value as Record<string, unknown>;
    const output: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(input)) {
      output[k] = sanitizeForFirestore(v);
    }
    return output;
  }
  return value;
}

/** The first side to go, as the lesson's presence records it — the moment the
 *  lesson ended, for billing and for the time both apps show. */
interface LessonDeparture {
  atMs: number;
  role: LessonRole;
  /** Left on purpose, or cut off without coming back. */
  reason: "left" | "connection_lost";
}

/** When one side went, if it has. Leaving on purpose counts from `leftAt`. A
 *  dropped connection counts from `lostAt`, but only while the side has no
 *  connection left: one that came back — or never went, and only saw an old
 *  connection's handler fire late — is still in the lesson. */
function sideDeparture(role: LessonRole, side: unknown): LessonDeparture | undefined {
  if (!side || typeof side !== "object") return undefined;
  const presence = side as LessonSidePresence;

  const leftAt = Number(presence.leftAt);
  if (Number.isFinite(leftAt) && leftAt > 0) return { atMs: leftAt, role, reason: "left" };

  const connected =
    typeof presence.connections === "object" &&
    presence.connections !== null &&
    Object.keys(presence.connections).length > 0;
  const lostAt = Number(presence.lostAt);
  if (!connected && Number.isFinite(lostAt) && lostAt > 0) {
    return { atMs: lostAt, role, reason: "connection_lost" };
  }
  return undefined;
}

/** The earlier of the two sides' departures, from `lessonPresence/{qid}`. */
function firstDeparture(presence: unknown): LessonDeparture | undefined {
  if (!presence || typeof presence !== "object") return undefined;
  const sides = presence as Record<string, unknown>;
  const departures = (["student", "teacher"] as const)
    .map((role) => sideDeparture(role, sides[role]))
    .filter((departure): departure is LessonDeparture => departure !== undefined);
  return departures.sort((a, b) => a.atMs - b.atMs)[0];
}

/** Removes what the apps watch while a lesson runs. Taking away the question
 *  node is what ends both apps' sessions. */
async function removeLiveLesson(questionId: string): Promise<void> {
  await db.ref(`questions/${questionId}`).remove();
  await db.ref(`lessonPresence/${questionId}`).remove();
}

async function resolveQuestionContext(questionId: string): Promise<{
  questionRef: admin.database.Reference;
  rtdbQuestion: Record<string, unknown>;
  studentUid: string;
  teacherUid: string;
  acceptedAtMs: number;
  startedAtMs: number | undefined;
  /** Seconds already banked as unbillable — the lesson was held for want of
   *  minutes and the student later bought more. See extendLessonMinutes. */
  heldSeconds: number;
  /** When the student's minutes run out. A lesson running past it is held, and
   *  everything after it is unbillable. Undefined for a lesson that started
   *  before allowances were recorded. */
  minutesDeadlineMs: number | undefined;
  /** The first side to leave or be cut off, if either has: the lesson ended
   *  then, however much later it is being settled. */
  departure: LessonDeparture | undefined;
}> {
  const questionRef = db.ref(`questions/${questionId}`);
  const questionSnap = await questionRef.once("value");
  if (!questionSnap.exists()) {
    throw new HttpsError("not-found", "Question not found in RTDB");
  }

  const rtdbQuestion = (questionSnap.val() ?? {}) as Record<string, unknown>;
  const fsQuestionSnap = await firestore.collection("questions").doc(questionId).get();
  const fsQuestion = (fsQuestionSnap.data() ?? {}) as Partial<QuestionDoc> & Record<string, unknown>;
  const presenceSnap = await db.ref(`lessonPresence/${questionId}`).once("value");

  const acceptedAtMs = firstNumber(
    toMillis(rtdbQuestion.acceptedAt),
    toMillis(fsQuestion.acceptedAt)
  );

  // The lesson runs from when both parties were fully connected (startLesson),
  // not from when the teacher accepted the invite. Firestore first: only the
  // backend writes it there, while either app can write to the live node.
  const startedAtMs = firstNumber(
    toMillis(fsQuestion.startedAt),
    toMillis(rtdbQuestion.startedAt)
  );

  const studentUid = firstString(
    rtdbQuestion.studentUid,
    rtdbQuestion.studentId,
    rtdbQuestion.userId,
    rtdbQuestion.askerUid,
    fsQuestion.studentUid
  );

  const teacherUid = firstString(
    rtdbQuestion.teacherUid,
    rtdbQuestion.teacherId,
    rtdbQuestion.acceptedByTeacher,
    rtdbQuestion.tutorUid,
    rtdbQuestion.responderUid,
    fsQuestion.acceptedByTeacher,
    fsQuestion.teacherUid
  );

  if (!studentUid || !teacherUid) {
    const keys = Object.keys(rtdbQuestion).sort().join(", ") || "none";
    throw new HttpsError(
      "failed-precondition",
      `Question is missing participants (RTDB keys: ${keys})`
    );
  }

  if (!acceptedAtMs) {
    throw new HttpsError("failed-precondition", "Question is missing acceptedAt");
  }

  const heldSecondsValue = Number(
    fsQuestion.heldSeconds ?? (rtdbQuestion.heldSeconds as number | undefined) ?? 0
  );

  return {
    questionRef,
    rtdbQuestion,
    studentUid,
    teacherUid,
    acceptedAtMs,
    startedAtMs,
    heldSeconds: Number.isFinite(heldSecondsValue) && heldSecondsValue > 0 ? heldSecondsValue : 0,
    minutesDeadlineMs: firstNumber(
      toMillis(fsQuestion.minutesDeadlineAt),
      toMillis(rtdbQuestion.minutesDeadlineAt)
    ),
    departure: firstDeparture(presenceSnap.val()),
  };
}

/** Everything `resolveQuestionContext` establishes about a lesson being ended.
 *  Derived from that function so the two cannot drift apart. */
type QuestionContext = Awaited<ReturnType<typeof resolveQuestionContext>>;

/** Whether a question with this status has reached a state no further ending
 *  can change: settled, or written off. */
function isEndedStatus(status: unknown): boolean {
  return status === "completed" || status === "cancelled";
}

/** A lesson as it was settled: who ended it, and the time both apps show. */
interface SettledLesson {
  endedBy: LessonDoc["endedBy"];
  /** How long it ran, to the second, holds excluded. */
  lessonSeconds: number;
  /** `lessonSeconds` rounded to the minutes billed, in seconds. */
  durationSeconds: number;
}

/**
 * Settles a lesson — charges the student, pays the teacher and records the
 * question completed — then removes its live RTDB node.
 *
 * The lesson ends with the first side to go: the moment it left, or lost its
 * connection and did not come back (see LessonDeparture). Only when neither
 * side has gone — the hard cap, say — does it end now. One algorithm, run once,
 * so the time the student pays for is the time the teacher is paid for, and
 * the time both apps show.
 *
 * A question that had already ended is not billed again, and undefined is
 * returned. Its node is removed all the same, since whatever ended the
 * question may have died before it could, and the apps end on its removal.
 */
async function migrateQuestionToFirestore(
  questionId: string,
  calledBy: LessonDoc["endedBy"],
  context: QuestionContext
): Promise<SettledLesson | undefined> {
  const {
    questionRef,
    rtdbQuestion,
    studentUid,
    teacherUid,
    acceptedAtMs,
    startedAtMs,
    heldSeconds: bankedHeldSeconds,
    minutesDeadlineMs,
    departure,
  } = context;
  // Whoever went first ended the lesson, whichever call is settling it: the
  // other app reacts to them going within moments, and can get here first.
  const endedBy: LessonDoc["endedBy"] = departure?.role ?? calledBy;
  logger.info(
    `[lessons] migrateQuestionToFirestore start qid=${questionId} endedBy=${endedBy} calledBy=${calledBy} departure=${departure ? `${departure.role}:${departure.reason}@${departure.atMs}` : "none"} studentUid=${studentUid} teacherUid=${teacherUid}`
  );
  const nowMs = Timestamp.now().toMillis();

  const lessonRecord = await loadLessonDocByQuestionId(questionId);
  const pricing = await resolveLessonPricing(studentUid, lessonRecord?.data);
  const { currencyCode, pricePerMinute, teacherShare, exchangeRateToUsd } = pricing;

  // Bill from the lesson's start — see billingStartMillis. Falling back to now
  // only when there is no usable start means a lesson with none bills zero
  // rather than billing from an unknown point.
  const billingStartMs = billingStartMillis(startedAtMs, acceptedAtMs) ?? nowMs;

  // Kept within the lesson: a departure is never before its start, and never
  // later than now.
  const endedAtMs = departure
    ? Math.min(nowMs, Math.max(billingStartMs, departure.atMs))
    : nowMs;
  const endedAt = Timestamp.fromMillis(endedAtMs);

  // Time the lesson spent held for want of minutes is not billed: the student
  // had already used everything they bought, and nothing was taught while the
  // two of them waited. `heldSeconds` is what earlier holds banked when the
  // student topped up; the final term is a hold still open at the end, which
  // is the ordinary case — the student chose not to buy and closed the lesson.
  const openHoldSeconds =
    minutesDeadlineMs === undefined
      ? 0
      : Math.max(0, Math.floor((endedAtMs - minutesDeadlineMs) / 1000));
  const heldSeconds = Math.max(0, Math.round(bankedHeldSeconds)) + openHoldSeconds;
  const billableEndedAtMs = Math.max(billingStartMs, endedAtMs - heldSeconds * 1000);

  const {
    rawSeconds,
    roundedSeconds,
    roundedMinutes,
    minutesToCharge: roundedMinutesToCharge,
    cost,
  } = calculateBilling(billingStartMs, billableEndedAtMs, pricePerMinute, teacherShare);

  // A teacher's welcome bonus (./emailRewards) raises their share on its first
  // minutes. It is read now rather than stamped at start, so a lesson only
  // draws on what is actually left when it is settled.
  const teacherRef = firestore.collection("users").doc(teacherUid);
  const teacherBonus = readTeacherBonus((await teacherRef.get()).data()?.teacherBonus);
  const { teacherEarnings, bonusMinutesUsed, effectiveShare } = applyTeacherBonus(
    cost,
    roundedMinutes,
    teacherShare,
    teacherBonus?.share ?? teacherShare,
    teacherBonus?.minutesRemaining ?? 0
  );
  const migratedQuestion = sanitizeForFirestore(rtdbQuestion) as Record<string, unknown>;
  logger.info(
    `[lessons] migrateQuestionToFirestore payload qid=${questionId} rtdbKeys=${Object.keys(rtdbQuestion).sort().join(",") || "none"}`
  );

  logger.info(
    `[lessons] cost computed qid=${questionId} rawSeconds=${rawSeconds} roundedSeconds=${roundedSeconds} heldSeconds=${heldSeconds} currency=${currencyCode} pricePerMinute=${pricePerMinute} cost=${cost} teacherShare=${teacherShare} bonusMinutesUsed=${bonusMinutesUsed} effectiveShare=${effectiveShare} teacherEarnings=${teacherEarnings}`
  );

  const qDocRef = firestore.collection("questions").doc(questionId);
  const studentRef = firestore.collection("users").doc(studentUid);

  // Callers settle whenever the live node exists, and the node outlives the
  // billing: it is removed only after this commits. A call that dies in
  // between leaves it for the other app, a retry or the hard cap to find, and
  // two calls ending the lesson at once both find it. So the status is checked
  // in the transaction that bills, and an ended question is not billed again.
  const alreadyEnded = await firestore.runTransaction(async (tx) => {
    const status = ((await tx.get(qDocRef)).data() as Partial<QuestionDoc> | undefined)?.status;
    if (isEndedStatus(status)) return status;

    // Read with the status, since a transaction reads before it writes — and
    // so the minutes drawn from each purchase are what it holds as it is billed.
    const purchasesSnap =
      roundedMinutesToCharge > 0
        ? await tx.get(studentRef.collection("purchases").where("status", "==", "active").limit(50))
        : undefined;

    tx.set(
      qDocRef,
      {
        ...migratedQuestion,
        state: "ended",
        status: "completed",
        studentUid,
        acceptedByTeacher: teacherUid,
        teacherId: teacherUid,
        participants: [studentUid, teacherUid],
        durationSeconds: roundedSeconds,
        lessonSeconds: rawSeconds,
        heldSeconds,
        currencyCode,
        pricePerMinute,
        exchangeRateToUsd,
        teacherShare,
        teacherBonusMinutesUsed: bonusMinutesUsed,
        effectiveTeacherShare: effectiveShare,
        cost,
        teacherEarnings,
        // Legacy aliases for clients still reading the old field names.
        costPerMinute: pricePerMinute,
        commissionRate: teacherShare,
        endedBy,
        ...(departure?.reason === "connection_lost" ? { endedReason: "connection_lost" } : {}),
        endedAt,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    if (lessonRecord) {
      tx.set(
        lessonRecord.ref,
        {
          // Completed with its billing. The caller marks it again afterwards,
          // but a call that dies first would leave a billed lesson in progress,
          // and the calls that clear up after it leave the lesson alone.
          status: "completed",
          currencyCode,
          pricePerMinute,
          teacherShare,
          teacherBonusMinutesUsed: bonusMinutesUsed,
          effectiveTeacherShare: effectiveShare,
          exchangeRateToUsd,
          cost,
          teacherEarnings,
          billedSeconds: roundedSeconds,
          durationSeconds: roundedSeconds,
          lessonSeconds: rawSeconds,
          endedBy,
          endedAt,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    tx.set(
      studentRef,
      {
        questions: FieldValue.arrayUnion(questionId),
        remainingMinutes: FieldValue.increment(-roundedMinutesToCharge),
        totalMinutesUsed: FieldValue.increment(roundedMinutesToCharge),
      },
      { merge: true }
    );
    tx.set(
      teacherRef,
      {
        questions: FieldValue.arrayUnion(questionId),
        totalMinutes: FieldValue.increment(roundedMinutes),
        totalEarnings: FieldValue.increment(teacherEarnings),
        earnings: FieldValue.increment(teacherEarnings),
        totalRevenueGenerated: FieldValue.increment(cost),
        ...(bonusMinutesUsed > 0
          ? { teacherBonus: { minutesRemaining: FieldValue.increment(-bonusMinutesUsed) } }
          : {}),
      },
      { merge: true }
    );

    if (purchasesSnap) {
      const sortedPurchases = [...purchasesSnap.docs].sort((a, b) => {
        const aTs = (a.data() as PurchaseDoc).purchasedAt?.toMillis?.() ?? 0;
        const bTs = (b.data() as PurchaseDoc).purchasedAt?.toMillis?.() ?? 0;
        return aTs - bTs;
      });

      let minutesToConsume = roundedMinutesToCharge;
      for (const purchaseDoc of sortedPurchases) {
        if (minutesToConsume <= 0) break;

        const purchase = purchaseDoc.data() as PurchaseDoc;
        const purchaseRef = purchaseDoc.ref;

        const currentRemaining = Math.max(0, Number(purchase.minutesRemaining ?? 0));
        if (currentRemaining <= 0) {
          tx.set(
            purchaseRef,
            {
              status: "expired",
              updatedAt: Timestamp.now(),
            },
            { merge: true }
          );
          continue;
        }

        const usedNow = Math.min(currentRemaining, minutesToConsume);
        const nextRemaining = Math.max(0, Math.round((currentRemaining - usedNow) * 100) / 100);
        minutesToConsume = Math.max(0, Math.round((minutesToConsume - usedNow) * 100) / 100);

        tx.set(
          purchaseRef,
          {
            minutesRemaining: nextRemaining,
            minutesUsed: FieldValue.increment(usedNow),
            status: nextRemaining === 0 ? "expired" : "active",
            updatedAt: Timestamp.now(),
          },
          { merge: true }
        );
      }

      const consumedFromPurchases = roundedMinutesToCharge - minutesToConsume;
      tx.set(
        studentRef,
        {
          purchaseMinutesConsumed: FieldValue.increment(consumedFromPurchases),
        },
        { merge: true }
      );

      logger.info(
        `[lessons] purchase consumption qid=${questionId} studentUid=${studentUid} roundedMinutes=${roundedMinutesToCharge} consumedFromPurchases=${consumedFromPurchases} remainingUnmapped=${minutesToConsume}`
      );
    }

    return undefined;
  });

  if (alreadyEnded) {
    logger.info(
      `[lessons] migrateQuestionToFirestore skipped qid=${questionId} status=${alreadyEnded}: already ended, nothing billed`
    );
  } else {
    logger.info(`[lessons] migrateQuestionToFirestore firestore transaction committed qid=${questionId}`);
  }

  const existsBeforeRemove = (await questionRef.once("value")).exists();
  logger.info(
    `[lessons] migrateQuestionToFirestore removing RTDB question qid=${questionId} existsBeforeRemove=${existsBeforeRemove}`
  );
  await removeLiveLesson(questionId);
  logger.info(`[lessons] migrateQuestionToFirestore RTDB question removed qid=${questionId}`);
  if (alreadyEnded) return undefined;
  return { endedBy, lessonSeconds: rawSeconds, durationSeconds: roundedSeconds };
}

type StoredQuestion = Partial<QuestionDoc> & Record<string, unknown>;

/** The question, if it has already reached a state no further ending can
 *  change. Read from Firestore, which outlives the live RTDB node. */
async function endedQuestion(questionId: string): Promise<StoredQuestion | undefined> {
  const snap = await firestore.collection("questions").doc(questionId).get();
  const question = snap.data() as StoredQuestion | undefined;
  return question && isEndedStatus(question.status) ? question : undefined;
}

/** The time a settled lesson ran, as both apps are told it — whichever of them
 *  ended it, and however it found out. Empty for a lesson written off before
 *  it started, or settled before the time was recorded. */
function settledTimes(question: StoredQuestion): { lessonSeconds?: number; durationSeconds?: number } {
  const times: { lessonSeconds?: number; durationSeconds?: number } = {};
  if (typeof question.lessonSeconds === "number") times.lessonSeconds = question.lessonSeconds;
  if (typeof question.durationSeconds === "number") times.durationSeconds = question.durationSeconds;
  return times;
}

/**
 * Adds minutes to a lesson the student is in right now, and lifts the hold.
 *
 * Called when a purchase lands (see ./payments). A student whose minutes ran
 * out mid-lesson is held rather than cut off, so buying more has to reach the
 * lesson already running, not just their balance.
 *
 * The wait itself is banked as `heldSeconds` and subtracted when the lesson is
 * billed: the new deadline runs from now rather than from the old one, so the
 * minutes just bought are not eaten by the time spent deciding to buy them.
 *
 * Returns whether a lesson was found and extended.
 */
export async function extendLessonMinutes(
  studentUid: string,
  addedMinutes: number
): Promise<boolean> {
  const minutes = Math.floor(Number(addedMinutes));
  if (!studentUid || !Number.isFinite(minutes) || minutes <= 0) return false;

  const snap = await firestore
    .collection("questions")
    .where("studentUid", "==", studentUid)
    .where("status", "==", "in_progress")
    .limit(1)
    .get();

  if (snap.empty) return false;
  const qRef = snap.docs[0].ref;

  const extended = await firestore.runTransaction(async (tx) => {
    const fresh = await tx.get(qRef);
    if (!fresh.exists) return undefined;

    const data = fresh.data() as QuestionDoc & {
      minutesAvailable?: number;
      minutesDeadlineAt?: unknown;
      heldSeconds?: number;
    };
    if (data.status !== "in_progress") return undefined;

    const now = Date.now();
    const deadlineMs = toMillis(data.minutesDeadlineAt) ?? now;
    const bankedHeld = Math.max(0, Math.round(Number(data.heldSeconds) || 0));
    const heldSeconds = bankedHeld + Math.max(0, Math.floor((now - deadlineMs) / 1000));
    const nextDeadlineMs = Math.max(now, deadlineMs) + minutes * 60_000;
    const minutesAvailable = Math.max(0, Math.round(Number(data.minutesAvailable) || 0)) + minutes;

    tx.update(qRef, {
      minutesAvailable,
      minutesDeadlineAt: Timestamp.fromMillis(nextDeadlineMs),
      heldSeconds,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { questionId: fresh.id, nextDeadlineMs, minutesAvailable, heldSeconds };
  });

  if (!extended) return false;

  // The apps watch the live node, so this is what lifts the hold on screen.
  await db.ref(`questions/${extended.questionId}`).update({
    minutesAvailable: extended.minutesAvailable,
    minutesDeadlineAt: extended.nextDeadlineMs,
    heldSeconds: extended.heldSeconds,
    updatedAt: Date.now(),
  });

  logger.info(
    `[lessons] extended lesson qid=${extended.questionId} student=${studentUid} addedMinutes=${minutes} minutesAvailable=${extended.minutesAvailable} heldSeconds=${extended.heldSeconds}`
  );
  return true;
}

/** Arms the grace period that ends a lesson the student never joined, and the
 *  later check that ends one that never started. Called when a teacher accepts,
 *  since that is when the teacher starts waiting. */
export async function enqueueAbandonedLessonCheck(questionId: string): Promise<void> {
  const queue = getFunctions().taskQueue("endAbandonedLesson");
  await queue.enqueue(
    { questionId },
    { scheduleDelaySeconds: ABANDONED_LESSON_GRACE_SECONDS }
  );
  await queue.enqueue(
    { questionId, unstarted: true },
    { scheduleDelaySeconds: UNSTARTED_LESSON_TIMEOUT_SECONDS }
  );
}

// ─── startLesson ──────────────────────────────────────────────────────────────
// FR-B-006, FR-B-010
// Called by both apps as they connect. The call that starts the lesson creates
// the /lessons doc, locks pricing, publishes the student's minutes deadline and
// schedules the 30-minute hard-cap task — and billing runs from that moment.
//
// An app that sends `ready` has it start only once both participants have
// finished connecting: `ready: false` as its chat connects, which records that
// it turned up, then `ready: true` once it is fully in the lesson. Nobody is
// billed for the connecting phase, and a lesson cancelled during it never
// starts at all (see endLesson). A call without `ready` starts the lesson at
// once, as every app did before.

export const startLesson = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const { questionId, ready } = req.data as { questionId: string; ready?: unknown };
  if (!questionId) throw new HttpsError("invalid-argument", "questionId required");

  const qRef = firestore.collection("questions").doc(questionId);
  const qSnap = await qRef.get();
  if (!qSnap.exists) throw new HttpsError("not-found", "Question not found");

  const q = qSnap.data() as QuestionDoc;

  // Guard: only the teacher or student on this question may call startLesson
  if (q.studentUid !== uid && q.acceptedByTeacher !== uid) {
    throw new HttpsError("permission-denied", "Not a participant in this lesson");
  }

  logger.info(
    `[lessons] startLesson authorized qid=${questionId} uid=${uid} questionStatus=${q.status} acceptedByTeacher=${q.acceptedByTeacher ?? "none"} ready=${String(ready)}`
  );

  if (typeof ready === "boolean") {
    return startWhenBothReady(questionId, qRef, q, uid, ready);
  }

  // Both apps call this as they connect, so arriving second is normal rather
  // than an error: record the arrival and hand back the lesson already running.
  // This is also the only record of who actually turned up — endAbandonedLesson
  // writes off a lesson the student never joined, and it reads this.
  await qRef.update({ joinedParticipants: FieldValue.arrayUnion(uid) });

  if (q.lessonId) {
    return { lessonId: q.lessonId };
  }

  if (q.status !== "accepted") {
    throw new HttpsError("failed-precondition", `Cannot start lesson in status: ${q.status}`);
  }

  const inputs = await readLessonStartInputs(questionId, q);
  const start = lessonStartWrites(questionId, q, inputs, uuidv4(), new Date());

  const batch = firestore.batch();
  batch.set(firestore.collection("lessons").doc(start.lessonId), start.lesson);
  batch.update(qRef, start.questionUpdate);
  await batch.commit();
  logger.info(
    `[lessons] startLesson firestore batch committed lessonId=${start.lessonId} qid=${questionId} currency=${inputs.pricing.currency} pricePerMinute=${inputs.pricing.pricePerMinute} teacherShare=${inputs.pricing.teacherShare}`
  );

  await publishLessonStart(questionId, start);
  return { lessonId: start.lessonId };
});

/**
 * startLesson for an app that reports `ready`. The lesson starts on the report
 * that makes both participants ready, and on that report alone: two arriving
 * together are serialised by the transaction, so exactly one of them sees both
 * and claims the start.
 */
async function startWhenBothReady(
  questionId: string,
  qRef: FirebaseFirestore.DocumentReference,
  q: QuestionDoc,
  uid: string,
  ready: boolean
): Promise<{ lessonId: string | null; started: boolean }> {
  // Priced beforehand, so the transaction only writes — and only for a report
  // that could be the one to start the lesson.
  const inputs =
    ready && !q.lessonId && q.status === "accepted"
      ? await readLessonStartInputs(questionId, q)
      : undefined;

  const outcome = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(qRef);
    const current = snap.data() as QuestionDoc;
    const arrival = {
      // Still the record of who turned up — see endAbandonedLesson.
      joinedParticipants: FieldValue.arrayUnion(uid),
      ...(ready ? { readyParticipants: FieldValue.arrayUnion(uid) } : {}),
    };

    const readyNow = new Set(current.readyParticipants ?? []);
    if (ready) readyNow.add(uid);
    const bothReady =
      readyNow.has(current.studentUid) &&
      current.acceptedByTeacher !== undefined &&
      readyNow.has(current.acceptedByTeacher);

    if (current.lessonId || !bothReady || current.status !== "accepted" || !inputs) {
      tx.update(qRef, arrival);
      return { start: undefined, lessonId: current.lessonId ?? null };
    }

    const start = lessonStartWrites(questionId, current, inputs, uuidv4(), new Date());
    tx.set(firestore.collection("lessons").doc(start.lessonId), start.lesson);
    tx.update(qRef, { ...arrival, ...start.questionUpdate });
    return { start, lessonId: start.lessonId };
  });

  if (outcome.start) {
    logger.info(
      `[lessons] startLesson both participants ready lessonId=${outcome.lessonId} qid=${questionId}`
    );
    await publishLessonStart(questionId, outcome.start);
  } else {
    logger.info(
      `[lessons] startLesson recorded uid=${uid} ready=${ready} qid=${questionId} lessonId=${outcome.lessonId ?? "none"}`
    );
  }
  return { lessonId: outcome.lessonId, started: outcome.lessonId !== null };
}

/** What a lesson is priced and bounded by, read before it is started so the
 *  start itself only writes. */
interface LessonStartInputs {
  liveKitRoom: string;
  pricing: Awaited<ReturnType<typeof resolvePricingForStudent>>;
  connectionFeeCents: number;
  /** The student's balance in whole minutes. */
  minutesAvailable: number;
  teacherBonus: ReturnType<typeof readTeacherBonus>;
}

async function readLessonStartInputs(
  questionId: string,
  q: QuestionDoc
): Promise<LessonStartInputs> {
  // Lock pricing at the moment the lesson starts so RC changes mid-lesson
  // do not retroactively shift the price. Currency is resolved from the
  // student's profile (/users/{uid}.currency).
  const [pricing, connectionFeeCents, studentSnap, teacherSnap] = await Promise.all([
    resolvePricingForStudent(q.studentUid),
    getConnectionFeeCents(),
    firestore.collection("users").doc(q.studentUid).get(),
    firestore.collection("users").doc(q.acceptedByTeacher!).get(),
  ]);

  return {
    // The room acceptInvite stored with the question.
    liveKitRoom: (q as { agoraChannel?: string }).agoraChannel ?? `lesson_${questionId}`,
    pricing,
    connectionFeeCents,
    minutesAvailable: Math.max(
      0,
      Math.floor(Number((studentSnap.data() ?? {}).remainingMinutes) || 0)
    ),
    teacherBonus: readTeacherBonus((teacherSnap.data() ?? {}).teacherBonus),
  };
}

/** Everything starting a lesson writes, as of `now`. */
interface LessonStart {
  lessonId: string;
  lesson: LessonDoc;
  questionUpdate: Record<string, unknown>;
  rtdbUpdate: Record<string, unknown>;
}

function lessonStartWrites(
  questionId: string,
  q: QuestionDoc,
  inputs: LessonStartInputs,
  lessonId: string,
  now: Date
): LessonStart {
  const { pricing, connectionFeeCents, minutesAvailable, teacherBonus, liveKitRoom } = inputs;
  const hardCapAt = new Date(now.getTime() + HARD_CAP_MINUTES * 60 * 1000);
  const pricePerMinuteCents = Math.round(pricing.pricePerMinute * 100);

  // What the student can afford, turned into a moment both apps can count down
  // to. They hold the session there — the student is offered more minutes, the
  // teacher is told why — and nothing past it is billed.
  const minutesDeadlineMs = now.getTime() + minutesAvailable * 60_000;

  const lesson: LessonDoc = {
    questionId,
    studentUid: q.studentUid,
    teacherUid: q.acceptedByTeacher!,
    startedAt: Timestamp.fromDate(now),
    hardCapAt: Timestamp.fromDate(hardCapAt),
    baseRatePerMinCents: pricePerMinuteCents,
    connectionFeeCents,
    currencyCode: pricing.currency,
    pricePerMinute: pricing.pricePerMinute,
    teacherShare: pricing.teacherShare,
    exchangeRateToUsd: pricing.exchangeRateToUsd,
    status: "in_progress",
    liveKitRoom,
    liveKitTokenExpiry: Timestamp.fromDate(new Date(now.getTime() + 3600 * 1000)),
    // Simulated sessions stay identifiable all the way through to reporting.
    ...(q.isDemo ? { isDemo: true } : {}),
  };

  // The live figure shows the welcome-bonus share while the teacher has bonus
  // minutes left. Settlement splits a lesson that outlasts them, so this is an
  // estimate at the edge; `teacherShare` itself stays the base rate.
  const teacherSharePercent = Math.round((teacherBonus?.share ?? pricing.teacherShare) * 100);

  return {
    lessonId,
    lesson,
    questionUpdate: {
      status: "in_progress",
      startedAt: Timestamp.fromDate(now),
      lessonId,
      minutesAvailable,
      minutesDeadlineAt: Timestamp.fromMillis(minutesDeadlineMs),
      heldSeconds: 0,
      currencyCode: pricing.currency,
      pricePerMinute: pricing.pricePerMinute,
      teacherShare: pricing.teacherShare,
      exchangeRateToUsd: pricing.exchangeRateToUsd,
      updatedAt: FieldValue.serverTimestamp(),
    },
    // Keep RTDB question state aligned for real-time clients. Mirror the
    // pricing snapshot so the in-progress UI can render live earnings / cost
    // without re-querying Firestore mid-call; the apps count the session from
    // `startedAt`.
    rtdbUpdate: {
      status: "in_progress",
      questionId,
      studentUid: q.studentUid,
      teacherUid: q.acceptedByTeacher,
      acceptedByTeacher: q.acceptedByTeacher,
      teacherId: q.acceptedByTeacher,
      startedAt: now.getTime(),
      updatedAt: now.getTime(),
      minutesAvailable,
      minutesDeadlineAt: minutesDeadlineMs,
      heldSeconds: 0,
      currencyCode: pricing.currency,
      pricePerMinute: pricing.pricePerMinute,
      pricePerMinuteCents,
      teacherShare: pricing.teacherShare,
      teacherSharePercent,
      teacherBonusMinutesAvailable: teacherBonus?.minutesRemaining ?? 0,
      exchangeRateToUsd: pricing.exchangeRateToUsd,
      connectionFeeCents,
    },
  };
}

/** After a start has committed: tells the apps, and arms the hard cap. */
async function publishLessonStart(questionId: string, start: LessonStart): Promise<void> {
  logger.info(
    `[lessons] startLesson syncing RTDB question qid=${questionId} status=in_progress teacherId=${start.lesson.teacherUid}`
  );
  await db.ref(`questions/${questionId}`).update(start.rtdbUpdate);
  logger.info(`[lessons] startLesson RTDB sync complete qid=${questionId}`);

  // Enqueue the hard-cap enforcement task (FR-B-006)
  const capQueue = getFunctions().taskQueue("forceEndLesson");
  await capQueue.enqueue(
    { lessonId: start.lessonId },
    { scheduleDelaySeconds: HARD_CAP_MINUTES * 60 }
  );

  logger.info(`[lessons] started lessonId=${start.lessonId} qid=${questionId}`);
}

/**
 * Ends a lesson that never started — the question is still `accepted`, with no
 * lesson document, because the two sides had not both finished connecting.
 * Written off the way endAbandonedLesson writes off one nobody joined: nobody
 * is charged or paid, and it goes into neither participant's history. Returns
 * who ended it, or undefined for a lesson that did start, to be settled as usual.
 */
async function writeOffUnstartedLesson(
  questionId: string,
  uid: string
): Promise<LessonDoc["endedBy"] | undefined> {
  const qRef = firestore.collection("questions").doc(questionId);

  let teacherUid: string | undefined;
  const endedBy = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(qRef);
    if (!snap.exists) return undefined;

    const question = snap.data() as QuestionDoc;
    if (question.status !== "accepted" || question.lessonId) return undefined;
    if (uid !== question.studentUid && uid !== question.acceptedByTeacher) {
      throw new HttpsError("permission-denied", "Not a participant in this lesson");
    }

    teacherUid = question.acceptedByTeacher;
    const by: LessonDoc["endedBy"] = uid === question.studentUid ? "student" : "teacher";
    tx.update(qRef, {
      status: "cancelled",
      endedBy: by,
      endedReason: "cancelled_while_connecting",
      endedAt: FieldValue.serverTimestamp(),
      billedSeconds: 0,
      durationSeconds: 0,
      totalCents: 0,
      cost: 0,
      teacherEarnings: 0,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return by;
  });
  if (!endedBy) return undefined;

  // Removing the live node is what ends the other side's session.
  await removeLiveLesson(questionId);

  if (teacherUid) {
    const teacher = teacherUid;
    await releaseTeacherBusy(teacher, questionId).catch((error) => {
      logger.error(`[lessons] failed releasing teacher=${teacher} qid=${questionId}`, error);
    });
    // Free again, so offered whatever is waiting.
    await backfillPendingQuestionsForTeacher(teacher).catch((error) => {
      logger.error(`[lessons] backfill failed teacher=${teacher} qid=${questionId}`, error);
    });
  }
  return endedBy;
}

// ─── endLesson ────────────────────────────────────────────────────────────────
// FR-B-007, FR-B-010
// Called by student or teacher when they tap End.

export const endLesson = onCall(async (req) => {
  const debugContext: Record<string, unknown> = { stage: "init" };
  try {
    const uid = req.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required");
    debugContext.uid = uid;

    const { questionId } = req.data as { questionId: string };
    if (!questionId) throw new HttpsError("invalid-argument", "questionId required");
    debugContext.questionId = questionId;
    debugContext.stage = "validated-input";
    logger.info(`[lessons] endLesson start qid=${questionId} uid=${uid}`);

    // Only a lesson that started is billed. One ended while the two sides were
    // still connecting never did, and is written off instead of settled.
    const cancelledBy = await writeOffUnstartedLesson(questionId, uid);
    if (cancelledBy) {
      logger.info(
        `[lessons] endLesson cancelled before the lesson started qid=${questionId} endedBy=${cancelledBy}`
      );
      return { success: true, questionId, endedBy: cancelledBy, cancelledBeforeStart: true };
    }
    debugContext.stage = "checked-started";

    let context: Awaited<ReturnType<typeof resolveQuestionContext>>;
    try {
      context = await resolveQuestionContext(questionId);
    } catch (error) {
      // The live question node is removed as a lesson is settled, so its
      // absence is usually not a failure: it means the other side ended the
      // lesson first, or the grace-period task wrote it off. Both apps call
      // this — the one that did not press End reaches here — and a lesson that
      // is already over is a success for the caller, not an error to show them.
      const ended = await endedQuestion(questionId);
      if (ended) {
        logger.info(`[lessons] endLesson already ended qid=${questionId} uid=${uid}`);
        const isParticipant = uid === ended.studentUid || uid === ended.acceptedByTeacher;
        return {
          success: true,
          questionId,
          alreadyEnded: true,
          ...(isParticipant ? settledTimes(ended) : {}),
        };
      }
      throw error;
    }
    debugContext.stage = "loaded-rtdb-question";

    const rtdbKeys = Object.keys(context.rtdbQuestion).sort();
    logger.info(
      `[lessons] endLesson RTDB question loaded qid=${questionId} keys=${rtdbKeys.join(",") || "none"}`
    );

    debugContext.stage = "resolved-question-sources";
    debugContext.studentUid = context.studentUid;
    debugContext.teacherUid = context.teacherUid;

    logger.info(
      `[lessons] endLesson participants resolved qid=${questionId} studentUid=${context.studentUid} teacherUid=${context.teacherUid}`
    );

    if (uid !== context.studentUid && uid !== context.teacherUid) {
      throw new HttpsError("permission-denied", "Not a participant in this lesson");
    }
    debugContext.stage = "authorized";

    const callerRole: LessonDoc["endedBy"] = uid === context.studentUid ? "student" : "teacher";
    debugContext.callerRole = callerRole;

    debugContext.stage = "committing-firestore";
    logger.info(`[lessons] endLesson committing Firestore writes qid=${questionId}`);
    const settled = await migrateQuestionToFirestore(questionId, callerRole, context);

    if (!settled) {
      // Already over. The live node was still here because whatever ended the
      // lesson died before removing it, or is ending it right now. Nothing is
      // billed again. The node is gone now, which ends both apps' sessions,
      // and the teacher is freed in case that call never got that far.
      await releaseTeacherBusy(context.teacherUid, questionId).catch((releaseError) => {
        logger.error(
          `[lessons] endLesson failed releasing teacher=${context.teacherUid} qid=${questionId}`,
          releaseError
        );
      });
      logger.info(`[lessons] endLesson already ended, cleared the live node qid=${questionId} uid=${uid}`);
      const ended = await endedQuestion(questionId);
      return { success: true, questionId, alreadyEnded: true, ...(ended ? settledTimes(ended) : {}) };
    }
    const { endedBy } = settled;
    debugContext.endedBy = endedBy;

    const questionDoc = await firestore.collection("questions").doc(questionId).get();
    const lessonId = (questionDoc.data() as { lessonId?: string } | undefined)?.lessonId;
    if (lessonId) {
      // Who ended it, and when, went in with the billing — as of the first side
      // to go, which may be well before now. This only closes the lesson the
      // question names.
      await firestore.collection("lessons").doc(lessonId).set(
        {
          status: "completed",
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
      logger.info(`[lessons] endLesson lesson completed lessonId=${lessonId} qid=${questionId}`);
    }

    debugContext.stage = "completed";
    logger.info(
      `[lessons] endLesson migrated qid=${questionId} from RTDB to Firestore and marked ended`
    );

    // Free before the backfill below: it ranks the teacher, and a teacher
    // still marked busy is not eligible for anything.
    await releaseTeacherBusy(context.teacherUid, questionId).catch((releaseError) => {
      logger.error(
        `[lessons] endLesson failed releasing teacher=${context.teacherUid} qid=${questionId}`,
        releaseError
      );
    });

    logger.info(
      `[lessons] endLesson triggering dispatch backfill for teacher=${context.teacherUid} qid=${questionId} endedBy=${endedBy}`
    );
    try {
      await backfillPendingQuestionsForTeacher(context.teacherUid);
    } catch (backfillError) {
      const backfillMessage = backfillError instanceof Error
        ? backfillError.message
        : String(backfillError);
      logger.error(
        `[lessons] endLesson backfill failed qid=${questionId} teacher=${context.teacherUid} message=${backfillMessage}`
      );
    }

    // The settled time goes back to the caller, and to the other app when it
    // calls in turn, so both show the lesson's one total.
    return {
      success: true,
      questionId,
      endedBy,
      lessonSeconds: settled.lessonSeconds,
      durationSeconds: settled.durationSeconds,
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    const stack = error instanceof Error ? error.stack : undefined;
    logger.error(
      `[lessons] endLesson failed stage=${String(debugContext.stage)} qid=${String(debugContext.questionId ?? "unknown")} uid=${String(debugContext.uid ?? "unknown")} message=${message}`
    );
    logger.error(`[lessons] endLesson debugContext=${JSON.stringify(debugContext)}`);
    if (stack) {
      logger.error(`[lessons] endLesson stack=${stack}`);
    }
    if (error instanceof HttpsError) throw error;
    throw new HttpsError("internal", `endLesson failed: ${message}`);
  }
});

// ─── rateTeacher ────────────────────────────────────────────────────────────
// FR-B-010: callable — student rates the teacher for a finished lesson.

export const rateTeacher = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const data = req.data as {
    questionId?: string;
    teacherId?: string;
    rating?: number;
    comment?: string;
  };

  const questionId = data.questionId;
  const teacherId = data.teacherId;
  const rating = Number(data.rating);
  const comment = normalizedComment(data.comment);

  if (!questionId) throw new HttpsError("invalid-argument", "questionId required");
  if (!teacherId) throw new HttpsError("invalid-argument", "teacherId required");
  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    throw new HttpsError("invalid-argument", "rating must be an integer from 1 to 5");
  }

  const questionRef = firestore.collection("questions").doc(questionId);
  const teacherRef = firestore.collection("teachers").doc(teacherId);
  const ratingRef = teacherRef.collection("ratings").doc(questionId);

  // The live RTDB question is removed only after migrateQuestionToFirestore has
  // committed `status: "completed"` and `endedAt`, so its presence means the
  // lesson has not been finalized yet. Rejecting here — rather than letting the
  // transaction below fail on "Lesson must be completed" — is what lets the app
  // tell a race apart from a genuine refusal: RateSessionView retries only on a
  // failed-precondition whose message mentions finalizing.
  const liveQuestionSnap = await db.ref(`questions/${questionId}`).once("value");
  if (liveQuestionSnap.exists()) {
    logger.info(`[lessons] rateTeacher deferred, lesson still finalizing qid=${questionId}`);
    throw new HttpsError(
      "failed-precondition",
      "Lesson is still being finalized. Try rating again in a few seconds"
    );
  }

  await firestore.runTransaction(async (tx) => {
    const [questionSnap, teacherSnap, existingRatingSnap] = await Promise.all([
      tx.get(questionRef),
      tx.get(teacherRef),
      tx.get(ratingRef),
    ]);

    if (!questionSnap.exists) {
      throw new HttpsError("not-found", "Question not found");
    }

    const question = questionSnap.data() as QuestionDoc;
    if (question.studentUid !== uid) {
      throw new HttpsError("permission-denied", "Only the student in this lesson can rate it");
    }

    const ratedTeacherId = (question as QuestionDoc & { teacherUid?: string }).teacherUid;
    if (question.acceptedByTeacher !== teacherId && ratedTeacherId !== teacherId) {
      throw new HttpsError("failed-precondition", "teacherId does not match this question");
    }

    const q = question as QuestionDoc & {
      state?: string;
      acceptedAt?: unknown;
      createdAt?: unknown;
      startedAt?: unknown;
      endedAt?: unknown;
      lessonId?: string;
    };

    let lessonForRating: (LessonDoc & { endedAt?: unknown; status?: string }) | undefined;
    if (typeof q.lessonId === "string" && q.lessonId.trim().length > 0) {
      const lessonSnap = await tx.get(firestore.collection("lessons").doc(q.lessonId));
      if (lessonSnap.exists) {
        lessonForRating = lessonSnap.data() as LessonDoc & { endedAt?: unknown; status?: string };
      }
    }

    const lessonFinished = Boolean(
      lessonForRating && (
        lessonForRating.status === "completed" ||
        toTimestamp(lessonForRating.endedAt)
      )
    );
    const questionFinished = q.status === "completed" || q.state === "ended";
    if (!questionFinished && !lessonFinished) {
      throw new HttpsError("failed-precondition", "Lesson must be completed before rating");
    }

    if (existingRatingSnap.exists) {
      return;
    }

    const teacherData = (teacherSnap.data() ?? {}) as TeacherAggregateDoc;
    const ratingsSnap = await tx.get(teacherRef.collection("ratings"));
    const ratingCount = ratingsSnap.size;
    const currentAverage = Number.isFinite(Number(teacherData.averageRate))
      ? Number(teacherData.averageRate)
      : 0;
    const nextAverage = ratingCount === 0
      ? rating
      : ((ratingCount * currentAverage) + rating) / (ratingCount + 1);

    let startedAt =
      toTimestamp(q.startedAt) ??
      toTimestamp(q.acceptedAt) ??
      toTimestamp(q.createdAt);
    let endedAt = toTimestamp(q.endedAt);

    if (lessonForRating) {
      startedAt = toTimestamp(lessonForRating.startedAt) ?? startedAt;
      endedAt = toTimestamp(lessonForRating.endedAt) ?? endedAt;
    }

    const safeEndedAt = endedAt ?? Timestamp.now();
    const safeStartedAt = startedAt ?? safeEndedAt;

    const ratingDoc: TeacherRatingDoc = {
      startedAt: safeStartedAt,
      endedAt: safeEndedAt,
      studentId: uid,
      studentRate: rating,
    };
    if (comment) {
      ratingDoc.studentComment = comment;
    }

    tx.set(ratingRef, ratingDoc);
    tx.set(teacherRef, { averageRate: nextAverage, ratingCount: ratingCount + 1 }, { merge: true });
    // Mirror the score onto the question so the student who gave it can show it
    // in their own lesson history — they cannot read the teacher's ratings.
    tx.update(questionRef, { studentRating: rating, ratedAt: Timestamp.now() });
  });

  // The dispatcher ranks on the RTDB copy, so a rating that only reached
  // Firestore would never affect who gets the next question. Best-effort: the
  // rating itself is already recorded, and presence stamps it again the next
  // time this teacher comes online.
  await stampAuthoritativeRating(teacherId).catch((error) => {
    logger.warn(`[lessons] failed mirroring rating teacher=${teacherId}`, error);
  });

  return { success: true };
});

// ─── endAbandonedLesson — Cloud Tasks handler ────────────────────────────────
// Armed when a teacher accepts, and fires once the grace period is up.
//
// A teacher can legitimately claim a question its student has already given up
// on: the student's app stops waiting after a minute, while an invite stays
// valid for ninety seconds, and a student whose app was killed never tells
// anyone it left at all. The teacher was then left sitting in a room nobody
// joins, with the billing clock running from the moment they accepted and
// nothing on the server to stop it — the 30-minute cap is armed by startLesson,
// which never runs when there is no lesson to start.
//
// Writing the question off costs the student nothing, pays nothing, and removes
// the live node, which is what ends the teacher's session: both apps stop when
// that node disappears.
//
// A second, later check (`unstarted`) writes off a lesson the student did join
// but that never started, because the two apps never both finished connecting
// — see UNSTARTED_LESSON_TIMEOUT_SECONDS.

export const endAbandonedLesson = onTaskDispatched<{ questionId: string; unstarted?: boolean }>(
  {
    retryConfig: { maxAttempts: 2 },
    rateLimits: { maxConcurrentDispatches: 20 },
  },
  async (req) => {
    const { questionId, unstarted } = req.data;
    if (!questionId) {
      logger.warn("[lessons] endAbandonedLesson missing questionId payload");
      return;
    }

    const qRef = firestore.collection("questions").doc(questionId);

    let teacherUid: string | undefined;
    const endedReason = await firestore.runTransaction(async (tx) => {
      const snap = await tx.get(qRef);
      if (!snap.exists) return undefined;

      const question = snap.data() as QuestionDoc & { joinedParticipants?: string[] };

      // Anything already settled — ended by a participant, cancelled, or never
      // claimed in the first place — is none of this task's business.
      if (question.status !== "accepted" && question.status !== "in_progress") return undefined;

      const joined = Array.isArray(question.joinedParticipants)
        ? question.joinedParticipants
        : [];
      const neverStarted =
        unstarted === true && question.status === "accepted" && !question.lessonId;
      if (joined.includes(question.studentUid) && !neverStarted) return undefined;

      teacherUid = question.acceptedByTeacher;
      const reason = joined.includes(question.studentUid) ? "never_started" : "student_never_joined";
      tx.update(qRef, {
        status: "cancelled",
        endedBy: "system",
        endedReason: reason,
        endedAt: FieldValue.serverTimestamp(),
        billedSeconds: 0,
        durationSeconds: 0,
        totalCents: 0,
        cost: 0,
        teacherEarnings: 0,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return reason;
    });

    if (!endedReason) {
      logger.info(`[lessons] endAbandonedLesson skipped qid=${questionId} unstarted=${unstarted === true}`);
      return;
    }

    await removeLiveLesson(questionId);

    if (teacherUid) {
      await releaseTeacherBusy(teacherUid, questionId).catch((error) => {
        logger.error(`[lessons] endAbandonedLesson failed releasing teacher=${teacherUid}`, error);
      });
    }

    // A lesson document exists only if the lesson started: here, one the
    // teacher's app started on its own, as apps did before a lesson waited for
    // both sides.
    const lessonRecord = await loadLessonDocByQuestionId(questionId);
    if (lessonRecord) {
      await lessonRecord.ref.set(
        {
          status: "completed",
          endedBy: "system",
          endedAt: FieldValue.serverTimestamp(),
          billedSeconds: 0,
          cost: 0,
          teacherEarnings: 0,
          updatedAt: FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }

    logger.warn(`[lessons] endAbandonedLesson wrote off qid=${questionId} reason=${endedReason}`);
  }
);

/**
 * Settles a lesson no app ended — at the hard cap, or once a side that lost
 * its connection has stayed away — and frees its teacher. Returns what was
 * settled, or undefined for a lesson that had already ended, whose leftovers
 * it has cleared instead.
 */
async function endLessonAsSystem(
  questionId: string,
  caller: string
): Promise<SettledLesson | undefined> {
  const context = await resolveQuestionContext(questionId);
  const settled = await migrateQuestionToFirestore(questionId, "system", context);

  await releaseTeacherBusy(context.teacherUid, questionId).catch((error) => {
    logger.error(`[lessons] ${caller} failed releasing teacher=${context.teacherUid}`, error);
  });
  return settled;
}

// ─── forceEndLesson — Cloud Tasks handler ────────────────────────────────────
// FR-B-006: fires at hardCapAt (30 min after lesson start).
// If the lesson is still in_progress, end it as "system".

export const forceEndLesson = onTaskDispatched<{ lessonId: string }>(
  {
    retryConfig: { maxAttempts: 3 },
    rateLimits: { maxConcurrentDispatches: 20 },
  },
  async (req) => {
    const { lessonId } = req.data;
    logger.info(`[lessons] forceEndLesson fired lessonId=${lessonId}`);

    if (!lessonId) {
      logger.warn("[lessons] forceEndLesson missing lessonId payload");
      return;
    }

    const lSnap = await firestore.collection("lessons").doc(lessonId).get();
    if (!lSnap.exists) {
      logger.warn(`[lessons] forceEndLesson lesson not found lessonId=${lessonId}`);
      return;
    }

    const lesson = lSnap.data() as LessonDoc;
    const questionId = lesson.questionId;
    if (!questionId) {
      logger.warn(`[lessons] forceEndLesson lesson missing questionId lessonId=${lessonId}`);
      return;
    }

    const questionSnap = await db.ref(`questions/${questionId}`).once("value");
    if (!questionSnap.exists()) {
      logger.info(`[lessons] forceEndLesson RTDB question already migrated qid=${questionId}`);
      return;
    }

    const settled = await endLessonAsSystem(questionId, "forceEndLesson");

    // Ended already, by a call that died before removing the live node — this
    // task's own earlier attempt among them. The lesson stays as whatever
    // ended it recorded it, rather than rewritten as ended by the cap.
    if (!settled) {
      logger.info(`[lessons] forceEndLesson lesson already ended qid=${questionId} lessonId=${lessonId}`);
      return;
    }

    // Who ended it, and when, went in with the billing: a side that left or
    // was cut off long before the cap still ended it then.
    await firestore.collection("lessons").doc(lessonId).set(
      {
        status: "completed",
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info(
      `[lessons] forceEndLesson hard cap applied qid=${questionId} lessonId=${lessonId} endedBy=${settled.endedBy}`
    );
  }
);

// ─── A side that lost its connection ─────────────────────────────────────────
// Once its lesson has started, each app keeps a connection entry and a
// disconnect handler on its side of `lessonPresence` (see LessonSidePresence).
// When its connection drops, the database server stamps `lostAt`. That side
// then has LESSON_RECONNECT_GRACE_SECONDS to come back, while the other app
// shows it reconnecting. If it does not, the lesson ends as of the moment the
// connection dropped.
//
// The app still in the lesson ends it too when the grace runs out. This is
// what ends it when that app is not running either — both cut off at once, or
// the other phone locked with the app suspended — rather than leaving it to
// the hard cap.

/** Starts the grace period for a side whose connection has just dropped. */
export const onLessonConnectionLost = onValueWritten(
  "lessonPresence/{questionId}/{role}/lostAt",
  async (event) => {
    const lostAt = event.data.after.val();
    // Cleared rather than stamped: nothing to wait for.
    if (typeof lostAt !== "number") return;
    const { questionId, role } = event.params;
    if (role !== "student" && role !== "teacher") return;

    await getFunctions()
      .taskQueue("endLostLesson")
      .enqueue(
        { questionId, role, lostAt },
        { scheduleDelaySeconds: LESSON_RECONNECT_GRACE_SECONDS }
      );
    logger.info(`[lessons] connection lost qid=${questionId} role=${role} lostAt=${lostAt}`);
  }
);

/** Ends a lesson whose side stayed cut off for the whole grace period. */
export const endLostLesson = onTaskDispatched<{
  questionId: string;
  role: LessonRole;
  lostAt: number;
}>(
  {
    retryConfig: { maxAttempts: 3 },
    rateLimits: { maxConcurrentDispatches: 20 },
  },
  async (req) => {
    const { questionId, role, lostAt } = req.data;
    if (!questionId || (role !== "student" && role !== "teacher")) {
      logger.warn("[lessons] endLostLesson missing questionId or role");
      return;
    }

    const presence = (await db.ref(`lessonPresence/${questionId}`).once("value")).val() as
      | Record<string, unknown>
      | null;
    const departure = sideDeparture(role, presence?.[role]);
    // Back in time, or cut off again since — a later loss has a task of its
    // own. One that went on to leave is ended by leaving.
    if (departure?.reason !== "connection_lost" || departure.atMs !== lostAt) {
      logger.info(`[lessons] endLostLesson skipped qid=${questionId} role=${role}: reconnected`);
      return;
    }

    if (!(await db.ref(`questions/${questionId}`).once("value")).exists()) {
      // Over already. A disconnect handler that fired after the lesson ended
      // left this behind.
      await db.ref(`lessonPresence/${questionId}`).remove();
      logger.info(`[lessons] endLostLesson cleared presence left after the lesson qid=${questionId}`);
      return;
    }

    // Only a lesson that started is ended here. One still connecting is
    // endAbandonedLesson's to write off.
    const status = (
      (await firestore.collection("questions").doc(questionId).get()).data() as StoredQuestion | undefined
    )?.status;
    if (status !== "in_progress" && !isEndedStatus(status)) {
      logger.info(`[lessons] endLostLesson skipped qid=${questionId} status=${status ?? "none"}`);
      return;
    }

    const settled = await endLessonAsSystem(questionId, "endLostLesson");
    logger.warn(
      `[lessons] endLostLesson qid=${questionId} role=${role} lostAt=${lostAt} settled=${settled !== undefined} endedBy=${settled?.endedBy ?? "already"}`
    );
  }
);
