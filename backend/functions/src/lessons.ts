import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { getFunctions } from "firebase-admin/functions";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { v4 as uuidv4 } from "uuid";

import {
  QuestionDoc,
  LessonDoc,
  HARD_CAP_MINUTES,
  BASE_RATE_PER_MIN_CENTS,
  CONNECTION_FEE_CENTS,
  MIN_BILLABLE_SECONDS,
  ROUND_UP_SECONDS,
} from "./types";

const firestore = admin.firestore();

// ─── billing helpers ──────────────────────────────────────────────────────────

// FR-B-007: round raw seconds up to the next ROUND_UP_SECONDS boundary.
function billableSeconds(startedAt: Date, endedAt: Date): number {
  const rawSeconds = Math.floor((endedAt.getTime() - startedAt.getTime()) / 1000);
  if (rawSeconds < MIN_BILLABLE_SECONDS) return 0;
  return Math.ceil(rawSeconds / ROUND_UP_SECONDS) * ROUND_UP_SECONDS;
}

function totalCents(billedSecs: number): number {
  return CONNECTION_FEE_CENTS + Math.ceil((billedSecs / 60) * BASE_RATE_PER_MIN_CENTS);
}

async function finaliseLesson(
  lessonId: string,
  endedBy: LessonDoc["endedBy"]
): Promise<{ billedSeconds: number; totalCents: number }> {
  const lRef = firestore.collection("lessons").doc(lessonId);

  // Fetch messages before the transaction — read-only, no consistency required
  const messagesSnap = await firestore
    .collection("lessons")
    .doc(lessonId)
    .collection("messages")
    .orderBy("sentAt")
    .get();
  const messages = messagesSnap.docs.map((d) => d.data());

  return firestore.runTransaction(async (tx) => {
    const snap = await tx.get(lRef);
    if (!snap.exists) throw new HttpsError("not-found", "Lesson not found");

    const lesson = snap.data() as LessonDoc;
    if (lesson.status !== "in_progress") {
      // Idempotent — already ended (e.g. both sides hit End within 2s)
      return {
        billedSeconds: lesson.billedSeconds ?? 0,
        totalCents: lesson.totalCents ?? CONNECTION_FEE_CENTS,
      };
    }

    const endedAt = new Date();
    const billed = billableSeconds(lesson.startedAt.toDate(), endedAt);
    const charged = totalCents(billed);

    tx.update(lRef, {
      status: "completed",
      endedAt: Timestamp.fromDate(endedAt),
      billedSeconds: billed,
      totalCents: charged,
      endedBy,
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Mirror summary + session snapshot to the question doc
    const qRef = firestore.collection("questions").doc(lesson.questionId);
    tx.update(qRef, {
      status: "completed",
      endedAt: Timestamp.fromDate(endedAt),
      billedSeconds: billed,
      totalCents: charged,
      endedBy,
      participants: [lesson.studentUid, lesson.teacherUid],
      startTime: lesson.startedAt,
      endTime: Timestamp.fromDate(endedAt),
      messages,
      updatedAt: FieldValue.serverTimestamp(),
    });

    // Append questionId to history for both participants
    const studentRef = firestore.collection("users").doc(lesson.studentUid);
    const teacherRef = firestore.collection("users").doc(lesson.teacherUid);
    tx.set(studentRef, { history: FieldValue.arrayUnion(lesson.questionId) }, { merge: true });
    tx.set(teacherRef, { history: FieldValue.arrayUnion(lesson.questionId) }, { merge: true });

    logger.info(
      `[lessons] finalised lessonId=${lessonId} billed=${billed}s total=${charged}¢ by=${endedBy}`
    );

    return { billedSeconds: billed, totalCents: charged };
  });
}

// ─── startLesson ──────────────────────────────────────────────────────────────
// FR-B-006, FR-B-010
// Called by either client once the Agora audio channel is connected.
// Creates the /lessons doc and schedules the 30-minute hard-cap task.

export const startLesson = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const { questionId } = req.data as { questionId: string };
  if (!questionId) throw new HttpsError("invalid-argument", "questionId required");

  const qRef = firestore.collection("questions").doc(questionId);
  const qSnap = await qRef.get();
  if (!qSnap.exists) throw new HttpsError("not-found", "Question not found");

  const q = qSnap.data() as QuestionDoc;

  // Guard: only the teacher or student on this question may call startLesson
  if (q.studentUid !== uid && q.acceptedByTeacher !== uid) {
    throw new HttpsError("permission-denied", "Not a participant in this lesson");
  }

  if (q.status !== "accepted") {
    throw new HttpsError("failed-precondition", `Cannot start lesson in status: ${q.status}`);
  }

  // Idempotent: if lesson already exists return it
  if (q.lessonId) {
    return { lessonId: q.lessonId };
  }

  const lessonId = uuidv4();
  const now = new Date();
  const hardCapAt = new Date(now.getTime() + HARD_CAP_MINUTES * 60 * 1000);

  const agoraTokenSnap = await firestore
    .collection("questions")
    .doc(questionId)
    .get()
    .then((s) => s.data() as QuestionDoc);

  // Retrieve the Agora token from acceptInvite's stored channel
  const liveKitRoom = (agoraTokenSnap as { agoraChannel?: string }).agoraChannel
    ?? `lesson_${questionId}`;

  const lesson: LessonDoc = {
    questionId,
    studentUid: q.studentUid,
    teacherUid: q.acceptedByTeacher!,
    startedAt: Timestamp.fromDate(now),
    hardCapAt: Timestamp.fromDate(hardCapAt),
    baseRatePerMinCents: BASE_RATE_PER_MIN_CENTS,
    connectionFeeCents: CONNECTION_FEE_CENTS,
    status: "in_progress",
    liveKitRoom,
    liveKitTokenExpiry: Timestamp.fromDate(new Date(now.getTime() + 3600 * 1000)),
  };

  const batch = firestore.batch();
  batch.set(firestore.collection("lessons").doc(lessonId), lesson);
  batch.update(qRef, {
    status: "in_progress",
    startedAt: Timestamp.fromDate(now),
    lessonId,
    updatedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();

  // Enqueue the hard-cap enforcement task (FR-B-006)
  const capQueue = getFunctions().taskQueue("forceEndLesson");
  await capQueue.enqueue(
    { lessonId },
    { scheduleDelaySeconds: HARD_CAP_MINUTES * 60 }
  );

  logger.info(`[lessons] started lessonId=${lessonId} qid=${questionId}`);
  return { lessonId };
});

// ─── endLesson ────────────────────────────────────────────────────────────────
// FR-B-007, FR-B-010
// Called by student or teacher when they tap End.

export const endLesson = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const { lessonId } = req.data as { lessonId: string };
  if (!lessonId) throw new HttpsError("invalid-argument", "lessonId required");

  const lSnap = await firestore.collection("lessons").doc(lessonId).get();
  if (!lSnap.exists) throw new HttpsError("not-found", "Lesson not found");

  const lesson = lSnap.data() as LessonDoc;
  if (lesson.studentUid !== uid && lesson.teacherUid !== uid) {
    throw new HttpsError("permission-denied", "Not a participant in this lesson");
  }

  const endedBy: LessonDoc["endedBy"] =
    uid === lesson.studentUid ? "student" : "teacher";

  const result = await finaliseLesson(lessonId, endedBy);
  return result;
});

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
    logger.info(`[lessons] forceEndLesson fired for lessonId=${lessonId}`);

    const lSnap = await firestore.collection("lessons").doc(lessonId).get();
    if (!lSnap.exists) {
      logger.warn(`[lessons] forceEndLesson: lessonId=${lessonId} not found`);
      return;
    }

    const lesson = lSnap.data() as LessonDoc;
    if (lesson.status !== "in_progress") {
      logger.info(`[lessons] forceEndLesson: lessonId=${lessonId} already ${lesson.status}`);
      return;
    }

    await finaliseLesson(lessonId, "system");
    logger.info(`[lessons] forceEndLesson: hard cap applied lessonId=${lessonId}`);
  }
);
