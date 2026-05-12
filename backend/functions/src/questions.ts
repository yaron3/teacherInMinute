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

  const qid = uuidv4();

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

  // Writing this doc triggers dispatchQuestion via the Firestore onCreate trigger.
  await firestore.collection("questions").doc(qid).set(question);

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

  const qRef = firestore.collection("questions").doc(questionId);

  await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(qRef);
    if (!snap.exists) throw new HttpsError("not-found", "Question not found");

    const data = snap.data() as QuestionDoc;
    if (data.studentUid !== uid) throw new HttpsError("permission-denied", "Not your question");

    const cancellable: QuestionDoc["status"][] = ["searching", "accepted"];
    if (!cancellable.includes(data.status)) {
      throw new HttpsError("failed-precondition", `Cannot cancel a question with status: ${data.status}`);
    }

    tx.update(qRef, {
      status: "cancelled",
      updatedAt: FieldValue.serverTimestamp(),
    });
  });

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

    // FR-B-004: fail if another teacher already claimed it
    if (q.status !== "searching") {
      throw new HttpsError("already-exists", "Question already claimed by another teacher");
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

  // Mint LiveKit tokens for both parties
  const channelName = `lesson_${questionId}`;
  const [teacherToken, studentToken] = await Promise.all([
    mintLiveKitToken(channelName, teacherUid),
    mintLiveKitToken(channelName, studentUid),
  ]);

  // Push the student's token to them via FCM
  const [teacherRecord, studentFcmToken] = await Promise.all([
    db.ref(`teachers/${teacherUid}`).once("value").then((s) => s.val()),
    db.ref(`users/${studentUid}/fcmToken`).once("value").then((s) => s.val() as string | null),
  ]);

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

  // Store the LiveKit room name on the question for startLesson to use
  await qRef.update({
    agoraChannel: channelName,
    updatedAt: FieldValue.serverTimestamp(),
  });

  // Clear RTDB invite signals for ALL teachers who were invited — question is taken
  const qSnap = await qRef.get();
  const alreadyInvited: string[] = (qSnap.data() as QuestionDoc).alreadyInvited ?? [];
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
