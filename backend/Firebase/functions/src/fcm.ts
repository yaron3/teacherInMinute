import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

/** What FCM answers for a token that will never deliver again — the app was
 *  uninstalled, or the token was replaced. */
const DEAD_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

/**
 * Removes a teacher's push token that FCM has said is dead, if it is still the
 * one on record — the app may have registered a new one since.
 *
 * ./keepAlive keeps a teacher whose app has gone silent online for as long as
 * they have a push token. Without this, one who uninstalled the app while
 * available would keep that token, and their place in the pool, for good.
 */
async function forgetDeadToken(teacherUid: string, deadToken: string): Promise<void> {
  let dropped = false;
  // Never aborts: the first pass may see an empty local cache, and writing
  // back what is there is what lets the retry see the stored token.
  await admin
    .database()
    .ref(`teachers/${teacherUid}/fcmToken`)
    .transaction((current: string | null) => {
      dropped = current === deadToken;
      return dropped ? null : current;
    });
  if (dropped) logger.info(`[fcm] dropped dead push token teacher=${teacherUid}`);
}

// Teacher invite — data-only, high priority, TTL matches the wave timeout.
// The client renders a full-screen incoming-call UI from these fields.
export async function sendInvitePush(params: {
  teacherUid: string;
  fcmToken: string;
  questionId: string;
  topic: string;
  studentName: string;
  questionText: string;
  wave: number;
  ttlSeconds: number;
}): Promise<void> {
  const { teacherUid, fcmToken, questionId, topic, studentName, questionText, wave, ttlSeconds } =
    params;

  await admin.messaging().send({
    token: fcmToken,
    data: {
      type: "incoming_question",
      questionId,
      topic,
      studentName,
      questionText: questionText.slice(0, 300),
      wave: String(wave),
      // Carried in the payload as well as in `android.ttl` so the client can
      // expire its own notification with the invite. `ttl` only governs how
      // long FCM keeps trying to deliver; without this the client would have to
      // hardcode a copy of INVITE_EXPIRY_SECONDS and drift from it.
      ttlSeconds: String(ttlSeconds),
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
  }).catch(async (err) => {
    logger.warn(`FCM invite failed for token ${fcmToken}:`, err);
    if (!DEAD_TOKEN_CODES.has(err?.code)) return;
    // Swallowed like the send itself: the invite has already gone out through
    // RTDB, and a failed cleanup must not fail the wave that called this.
    await forgetDeadToken(teacherUid, fcmToken).catch((cleanupErr) =>
      logger.warn(`[fcm] failed dropping dead push token teacher=${teacherUid}`, cleanupErr)
    );
  });
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
