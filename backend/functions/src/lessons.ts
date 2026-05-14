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
} from "./types";

const firestore = admin.firestore();
const db = admin.database();

function firstString(...values: unknown[]): string | undefined {
  for (const value of values) {
    if (typeof value === "string" && value.trim().length > 0) {
      return value;
    }
  }
  return undefined;
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

async function resolveQuestionContext(questionId: string): Promise<{
  questionRef: admin.database.Reference;
  rtdbQuestion: Record<string, unknown>;
  studentUid: string;
  teacherUid: string;
}> {
  const questionRef = db.ref(`questions/${questionId}`);
  const questionSnap = await questionRef.once("value");
  if (!questionSnap.exists()) {
    throw new HttpsError("not-found", "Question not found in RTDB");
  }

  const rtdbQuestion = (questionSnap.val() ?? {}) as Record<string, unknown>;
  const fsQuestionSnap = await firestore.collection("questions").doc(questionId).get();
  const fsQuestion = (fsQuestionSnap.data() ?? {}) as Partial<QuestionDoc> & Record<string, unknown>;

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
    rtdbQuestion.teachedId,
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

  return {
    questionRef,
    rtdbQuestion,
    studentUid,
    teacherUid,
  };
}

async function migrateQuestionToFirestore(
  questionId: string,
  endedBy: LessonDoc["endedBy"],
  context: {
    questionRef: admin.database.Reference;
    rtdbQuestion: Record<string, unknown>;
    studentUid: string;
    teacherUid: string;
  }
): Promise<void> {
  const { questionRef, rtdbQuestion, studentUid, teacherUid } = context;
  const endedAt = Timestamp.now();
  const migratedQuestion = sanitizeForFirestore(rtdbQuestion) as Record<string, unknown>;

  const batch = firestore.batch();
  const qDocRef = firestore.collection("questions").doc(questionId);
  batch.set(
    qDocRef,
    {
      ...migratedQuestion,
      state: "ended",
      status: "completed",
      studentUid,
      acceptedByTeacher: teacherUid,
      teacherId: teacherUid,
      teachedId: teacherUid,
      participants: [studentUid, teacherUid],
      endedBy,
      endedAt,
      updatedAt: FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  const studentRef = firestore.collection("users").doc(studentUid);
  const teacherRef = firestore.collection("users").doc(teacherUid);
  batch.set(studentRef, { questions: FieldValue.arrayUnion(questionId) }, { merge: true });
  batch.set(teacherRef, { questions: FieldValue.arrayUnion(questionId) }, { merge: true });

  await batch.commit();
  await questionRef.remove();
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

  // Keep RTDB question state aligned for real-time clients.
  await db.ref(`questions/${questionId}`).update({
    status: "accepted",
    teacherId: q.acceptedByTeacher,
    teachedId: q.acceptedByTeacher,
    updatedAt: Date.now(),
  });

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

    const context = await resolveQuestionContext(questionId);
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

    const endedBy: LessonDoc["endedBy"] = uid === context.studentUid ? "student" : "teacher";
    debugContext.endedBy = endedBy;

    debugContext.stage = "committing-firestore";
    logger.info(`[lessons] endLesson committing Firestore writes qid=${questionId}`);
    await migrateQuestionToFirestore(questionId, endedBy, context);

    debugContext.stage = "completed";
    logger.info(
      `[lessons] endLesson migrated qid=${questionId} from RTDB to Firestore and marked ended`
    );

    return { success: true, questionId, endedBy };
  } catch (error) {
    logger.error("[lessons] endLesson failed", { error, debugContext });
    if (error instanceof HttpsError) throw error;
    const message = error instanceof Error ? error.message : String(error);
    throw new HttpsError("internal", `endLesson failed: ${message}`);
  }
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

    const context = await resolveQuestionContext(questionId);
    await migrateQuestionToFirestore(questionId, "system", context);

    await firestore.collection("lessons").doc(lessonId).set(
      {
        status: "completed",
        endedBy: "system",
        endedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    logger.info(`[lessons] forceEndLesson hard cap applied qid=${questionId} lessonId=${lessonId}`);
  }
);
