import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

// Teacher invite — data-only, high priority, TTL matches the wave timeout.
// The client renders a full-screen incoming-call UI from these fields.
export async function sendInvitePush(params: {
  fcmToken: string;
  questionId: string;
  topic: string;
  studentName: string;
  questionText: string;
  wave: number;
  ttlSeconds: number;
}): Promise<void> {
  const { fcmToken, questionId, topic, studentName, questionText, wave, ttlSeconds } = params;

  await admin.messaging().send({
    token: fcmToken,
    data: {
      type: "incoming_question",
      questionId,
      topic,
      studentName,
      questionText: questionText.slice(0, 300),
      wave: String(wave),
    },
    android: {
      priority: "high",
      ttl: ttlSeconds * 1000,
    },
    apns: {
      headers: {
        "apns-priority": "10",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + ttlSeconds),
      },
    },
  }).catch((err) => logger.warn(`FCM invite failed for token ${fcmToken}:`, err));
}

// Notify student that their question was accepted.
export async function sendAcceptedPush(params: {
  fcmToken: string;
  teacherName: string;
  questionId: string;
  agoraChannel: string;
  agoraToken: string;
  agoraUid: number;
}): Promise<void> {
  const { fcmToken, teacherName, questionId, agoraChannel, agoraToken, agoraUid } = params;

  await admin.messaging().send({
    token: fcmToken,
    notification: {
      title: "Teacher found!",
      body: `${teacherName} is ready to help.`,
    },
    data: {
      type: "question_accepted",
      questionId,
      agoraChannel,
      agoraToken,
      agoraUid: String(agoraUid),
    },
    android: { priority: "high" },
    apns: { headers: { "apns-priority": "10" } },
  }).catch((err) => logger.warn(`FCM accepted push failed for token ${fcmToken}:`, err));
}

// Notify student that no teacher was found.
export async function sendNoMatchPush(params: {
  fcmToken: string;
  questionId: string;
}): Promise<void> {
  const { fcmToken, questionId } = params;

  await admin.messaging().send({
    token: fcmToken,
    notification: {
      title: "No teacher available",
      body: "Sorry, no teacher is available right now. Please try again soon.",
    },
    data: { type: "no_match", questionId },
    android: { priority: "high" },
    apns: { headers: { "apns-priority": "10" } },
  }).catch((err) => logger.warn(`FCM no-match push failed for token ${fcmToken}:`, err));
}
