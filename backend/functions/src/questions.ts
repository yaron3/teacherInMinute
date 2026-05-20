import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { v4 as uuidv4 } from "uuid";

import { mintLiveKitToken } from "./agora";
import { sendAcceptedPush } from "./fcm";
import { QuestionDoc, DispatchInviteDoc, CONNECTION_FEE_CENTS } from "./types";

const db = admin.database();
const firestore = admin.firestore();

type LiveQuestionStatus = "searching" | "accepted" | "in_progress";

async function upsertLiveQuestion(
  questionId: string,
  patch: Record<string, unknown>,
  status: LiveQuestionStatus,
  reason: string
): Promise<void> {
  const payload = {
    ...patch,
    status,
    updatedAt: Date.now(),
  };

  logger.info(
    `[questions] upsertLiveQuestion start qid=${questionId} status=${status} reason=${reason} keys=${Object.keys(payload).sort().join(",")}`
  );
  await db.ref(`questions/${questionId}`).update(payload);
  logger.info(`[questions] upsertLiveQuestion done qid=${questionId} status=${status} reason=${reason}`);
}

async function cleanupRtdb(questionId: string, alreadyInvited: string[]): Promise<void> {
  logger.info(
    `[questions] cleanupRtdb start qid=${questionId} invitesToClear=${alreadyInvited.length}`
  );

  const questionRef = db.ref(`questions/${questionId}`);
  const questionExists = (await questionRef.once("value")).exists();
  logger.info(
    `[questions] cleanupRtdb precheck qid=${questionId} rtdbQuestionExists=${questionExists}`
  );

  await Promise.all([
    questionRef.remove(),
    ...alreadyInvited.map((tid) => db.ref(`teacherInvites/${tid}/${questionId}`).remove()),
  ]);

  logger.info(
    `[questions] cleanupRtdb done qid=${questionId} removedQuestion=${questionExists} removedTeacherInvites=${alreadyInvited.length}`
  );
}

// ─── createQuestion ───────────────────────────────────────────────────────────
// FR-B-010: callable — student initiates the question + dispatch pipeline.
// Writing the Firestore doc triggers dispatchQuestion automatically.

export const createQuestion = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const { topic, text, photoUrls = [], voiceMemoUrl } = req.data as {
    topic: string;
    text: string;
    photoUrls?: string[];
    voiceMemoUrl?: string;
  };

  if (!topic || !text?.trim()) {
    throw new HttpsError("invalid-argument", "topic and text are required");
  }

  const validTopics = ["algebra", "geometry", "trigonometry", "calculus", "statistics", "arithmetic"];
  if (!validTopics.includes(topic)) {
    throw new HttpsError("invalid-argument", `topic must be one of: ${validTopics.join(", ")}`);
  }

  if (text.trim().length < 10) {
    throw new HttpsError("invalid-argument", "Question text must be at least 10 characters");
  }

  const studentSnap = await firestore.collection("users").doc(uid).get();
  const remainingMinutes: number = (studentSnap.data()?.remainingMinutes as number | undefined) ?? 0;
  if (remainingMinutes < 2) {
    throw new HttpsError("resource-exhausted", "Not enough time left");
  }

  const qid = uuidv4();

  logger.info(`[questions] createQuestion start qid=${qid} student=${uid} topic=${topic}`);

  const question: QuestionDoc = {
    studentUid: uid,
    topic,
    text: text.trim(),
    photoUrls,
    ...(voiceMemoUrl ? { voiceMemoUrl } : {}),
    status: "searching",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    dispatchWave: 0,
    alreadyInvited: [],
  };

  const liveQuestion: Record<string, unknown> = {
    questionId: qid,
    studentUid: uid,
    topic,
    text: text.trim(),
    photoUrls,
    ...(voiceMemoUrl ? { voiceMemoUrl } : {}),
    dispatchWave: 0,
    createdAt: Date.now(),
  };

  await upsertLiveQuestion(qid, liveQuestion, "searching", "createQuestion");
  logger.info(`[questions] createQuestion RTDB-upsert done qid=${qid}`);

  // Writing this doc triggers dispatchQuestion via the Firestore onCreate trigger.
  await firestore.collection("questions").doc(qid).set(question);

  logger.info(
    `[questions] createQuestion firestore-set done qid=${qid} status=${question.status} dispatchWave=${question.dispatchWave}`
  );
  logger.info(`[questions] created qid=${qid} topic=${topic} student=${uid}`);
  return { questionId: qid, connectionFeeCents: CONNECTION_FEE_CENTS };
});

// ─── cancelQuestion ───────────────────────────────────────────────────────────
// FR-B-010: student cancels while still in "searching" state. Free before a
// teacher has accepted. We do not charge for pilot (no Stripe hold).

export const cancelQuestion = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const { questionId } = req.data as { questionId: string };
  if (!questionId) throw new HttpsError("invalid-argument", "questionId required");

  logger.info(`[questions] cancelQuestion requested qid=${questionId} by student=${uid}`);

  const qRef = firestore.collection("questions").doc(questionId);
  let alreadyInvited: string[] = [];

  await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(qRef);
    if (!snap.exists) throw new HttpsError("not-found", "Question not found");

    const data = snap.data() as QuestionDoc;
    logger.info(
      `[questions] cancelQuestion tx-read qid=${questionId} status=${data.status} alreadyInvited=${(data.alreadyInvited ?? []).length}`
    );
    if (data.studentUid !== uid) throw new HttpsError("permission-denied", "Not your question");

    const cancellable: QuestionDoc["status"][] = ["searching", "accepted"];
    if (!cancellable.includes(data.status)) {
      throw new HttpsError("failed-precondition", `Cannot cancel a question with status: ${data.status}`);
    }

    alreadyInvited = data.alreadyInvited ?? [];

    tx.update(qRef, {
      status: "cancelled",
      endedBy: "student",
      endedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

  await cleanupRtdb(questionId, alreadyInvited);

  logger.info(`[questions] cancelled qid=${questionId} by student=${uid}`);
  return { success: true };
});

// ─── acceptInvite ─────────────────────────────────────────────────────────────
// FR-B-004: atomic Firestore transaction guarantees exactly one teacher wins.
// Returns Agora token for the teacher; pushes token to student via FCM.

export const acceptInvite = onCall(async (req) => {
  const teacherUid = req.auth?.uid;
  if (!teacherUid) throw new HttpsError("unauthenticated", "Sign in required");

  const { questionId } = req.data as { questionId: string };
  if (!questionId) throw new HttpsError("invalid-argument", "questionId required");

  logger.info(`[questions] acceptInvite requested qid=${questionId} by teacher=${teacherUid}`);

  const qRef = firestore.collection("questions").doc(questionId);
  const inviteRef = qRef.collection("invites").doc(teacherUid);

  let studentUid = "";

  // Atomic claim — only one teacher can win
  await firestore.runTransaction(async (tx) => {
    const [qSnap, invSnap] = await Promise.all([tx.get(qRef), tx.get(inviteRef)]);

    if (!qSnap.exists) throw new HttpsError("not-found", "Question not found");
    if (!invSnap.exists) throw new HttpsError("not-found", "Invite not found");

    const q = qSnap.data() as QuestionDoc;
    const inv = invSnap.data() as DispatchInviteDoc;

    logger.info(
      `[questions] acceptInvite tx-read qid=${questionId} questionStatus=${q.status} inviteResponse=${inv.response} inviteWave=${inv.wave}`
    );

    // FR-B-004: fail only if someone else already claimed it.
    // "unanswered" means all waves timed out but no one accepted — a teacher with
    // a still-valid invite (INVITE_EXPIRY_SECONDS > WAVE_TIMEOUT_SECONDS * waves)
    // can still legitimately accept it.
    if (q.status === "accepted" || q.status === "in_progress" || q.status === "completed") {
      throw new HttpsError("already-exists", "Question already claimed by another teacher");
    }
    if (q.status === "cancelled") {
      throw new HttpsError("failed-precondition", "Question was cancelled by the student");
    }
    if (q.status !== "searching" && q.status !== "unanswered") {
      throw new HttpsError("failed-precondition", `Question is not available (status: ${q.status})`);
    }

    if (inv.response !== "pending") {
      throw new HttpsError("failed-precondition", "Invite is no longer pending");
    }

    // Check invite hasn't expired
    if (inv.expiresAt.toMillis() < Date.now()) {
      throw new HttpsError("deadline-exceeded", "Invite has expired");
    }

    studentUid = q.studentUid;

    tx.update(qRef, {
      status: "accepted",
      acceptedByTeacher: teacherUid,
      acceptedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    tx.update(inviteRef, { response: "accept" });
  });

  await upsertLiveQuestion(
    questionId,
    {
      studentUid,
      teacherUid,
      teacherId: teacherUid,
      acceptedByTeacher: teacherUid,
      acceptedAt: Date.now(),
    },
    "accepted",
    "acceptInvite"
  );

  // Mint LiveKit tokens for both parties
  const channelName = `lesson_${questionId}`;
  const [teacherToken, studentToken] = await Promise.all([
    mintLiveKitToken(channelName, teacherUid),
    mintLiveKitToken(channelName, studentUid),
  ]);

  // Snapshot both participants' name+image so lesson history can render without
  // cross-user reads (Firestore rules block students from reading teacher docs
  // and vice versa). These fields are frozen at accept-time on purpose.
  const [teacherRecord, studentFcmToken, teacherUserSnap, studentUserSnap] = await Promise.all([
    db.ref(`teachers/${teacherUid}`).once("value").then((s) => s.val()),
    db.ref(`users/${studentUid}/fcmToken`).once("value").then((s) => s.val() as string | null),
    firestore.collection("users").doc(teacherUid).get(),
    firestore.collection("users").doc(studentUid).get(),
  ]);

  const teacherUser = teacherUserSnap.data() ?? {};
  const studentUser = studentUserSnap.data() ?? {};
  const pickImage = (u: FirebaseFirestore.DocumentData): string =>
    (u.profileImageURL as string | undefined) ??
    (u.profilePhotoURL as string | undefined) ??
    (u.photoURL as string | undefined) ??
    "";

  if (studentFcmToken) {
    await sendAcceptedPush({
      fcmToken: studentFcmToken,
      teacherName: teacherRecord?.displayName ?? "Your teacher",
      questionId,
      agoraChannel: channelName,
      agoraToken: studentToken.token,
      agoraUid: 0,
    });
  }

  // Store the LiveKit room name + name/image snapshots on the question doc.
  await qRef.update({
    agoraChannel: channelName,
    teacherName: (teacherUser.fullName as string | undefined) ?? "",
    teacherImageURL: pickImage(teacherUser),
    studentName: (studentUser.fullName as string | undefined) ?? "",
    studentImageURL: pickImage(studentUser),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await upsertLiveQuestion(
    questionId,
    {
      agoraChannel: channelName,
      teacherName: (teacherUser.fullName as string | undefined) ?? "",
      teacherImageURL: pickImage(teacherUser),
      studentName: (studentUser.fullName as string | undefined) ?? "",
      studentImageURL: pickImage(studentUser),
    },
    "accepted",
    "acceptInvite-profile-sync"
  );

  // Clear RTDB invite signals for ALL teachers who were invited — question is taken
  const qSnap = await qRef.get();
  const alreadyInvited: string[] = (qSnap.data() as QuestionDoc).alreadyInvited ?? [];
  logger.info(
    `[questions] acceptInvite clearing teacher RTDB invites qid=${questionId} invitedCount=${alreadyInvited.length}`
  );
  await Promise.all(
    alreadyInvited.map((uid) => db.ref(`teacherInvites/${uid}/${questionId}`).remove())
  );

  logger.info(`[questions] accepted qid=${questionId} teacher=${teacherUid}`);

  return {
    liveKitRoom: channelName,
    liveKitToken: teacherToken.token,
    studentUid,
  };
});

// ─── getQuestionStatus ────────────────────────────────────────────────────────
// Polled by the student app every 3s while in "searching" state.
// Returns {status} plus LiveKit credentials if the question was accepted.

export const getQuestionStatus = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const { questionId } = req.data as { questionId: string };
  if (!questionId) throw new HttpsError("invalid-argument", "questionId required");

  const qSnap = await firestore.collection("questions").doc(questionId).get();
  if (!qSnap.exists) throw new HttpsError("not-found", "Question not found");

  const q = qSnap.data() as QuestionDoc;
  if (q.studentUid !== uid) throw new HttpsError("permission-denied", "Not your question");

  logger.info(`[questions] getQuestionStatus qid=${questionId} student=${uid} status=${q.status}`);

  if (q.status === "accepted" || q.status === "in_progress") {
    const roomName = `lesson_${questionId}`;
    const token = await mintLiveKitToken(roomName, uid);
    return { status: q.status, liveKitRoom: roomName, liveKitToken: token.token };
  }

  return { status: q.status };
});

// ─── declineInvite ────────────────────────────────────────────────────────────
// FR-B-010: teacher explicitly declines. Updates invite; accept_rate signal
// is recomputed by a scheduled function (deferred for pilot).

export const declineInvite = onCall(async (req) => {
  const teacherUid = req.auth?.uid;
  if (!teacherUid) throw new HttpsError("unauthenticated", "Sign in required");

  const { questionId } = req.data as { questionId: string };
  if (!questionId) throw new HttpsError("invalid-argument", "questionId required");

  logger.info(`[questions] declineInvite requested qid=${questionId} by teacher=${teacherUid}`);

  const inviteRef = firestore
    .collection("questions")
    .doc(questionId)
    .collection("invites")
    .doc(teacherUid);

  const snap = await inviteRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Invite not found");

  const inv = snap.data() as DispatchInviteDoc;
  if (inv.response !== "pending") {
    throw new HttpsError("failed-precondition", "Invite already responded to");
  }

  await inviteRef.update({ response: "decline" });

  // Remove RTDB signal for this teacher only — others still have their invite
  await db.ref(`teacherInvites/${teacherUid}/${questionId}`).remove();

  logger.info(`[questions] declined qid=${questionId} teacher=${teacherUid}`);
  return { success: true };
});
