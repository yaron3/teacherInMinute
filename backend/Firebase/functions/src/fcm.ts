import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { ANY_TOPIC } from "./scoring";

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

/** "Maya needs help with algebra", or "Maya needs help" for a question put to
 *  every teacher. Matches the Android client's AndroidIncomingQuestionNotifier. */
export function inviteAlertTitle(studentName: string, topic: string): string {
  const name = studentName || "A student";
  return topic === ANY_TOPIC || !topic ? `${name} needs help` : `${name} needs help with ${topic}`;
}

// Teacher invite — high priority, TTL matches the wave timeout.
//
// Data-only on Android, where the client posts the notification itself
// (AndroidIncomingQuestionNotifier) so it controls the channel and timeout.
// iOS shows nothing for a data-only push to an app that is suspended or killed,
// and that is the only state a push matters in, so the APNs override carries a
// visible alert. Its collapse id is the identifier the iOS client gives the
// same invite when it posts one locally (LocalNotificationService), so the two
// collapse into one notification rather than announcing the invite twice.
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
      // A question for any teacher has no topic to name in the notification,
      // which then reads "<student> needs help".
      topic: topic === ANY_TOPIC ? "" : topic,
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
        "apns-push-type": "alert",
        "apns-expiration": String(Math.floor(Date.now() / 1000) + ttlSeconds),
        "apns-collapse-id": `teacher-question-${questionId}`,
      },
      payload: {
        aps: {
          alert: {
            title: inviteAlertTitle(studentName, topic),
            body: questionText.slice(0, 300),
          },
          sound: "default",
        },
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

/** The Android channel AndroidLocalNotificationManager creates for general
 *  updates, so an admin message does not land in the incoming-questions one. */
const UPDATES_CHANNEL_ID = "teacher_minute_updates";

/**
 * Sends one admin-composed notification to each of `tokens`. A visible
 * `notification` payload, so the system posts it on both platforms while the
 * app is away; in the foreground iOS shows it as a banner and the Android
 * client posts it itself. Reports per token instead of throwing, so one dead
 * device never stops the rest.
 */
export async function sendAdminPush(params: {
  tokens: string[];
  title: string;
  body: string;
}): Promise<{ sent: number; dead: string[]; failed: string[] }> {
  const { tokens, title, body } = params;
  if (tokens.length === 0) return { sent: 0, dead: [], failed: [] };

  const response = await admin.messaging().sendEach(
    tokens.map((token) => ({
      token,
      notification: { title, body },
      data: { type: "admin_message" },
      android: { priority: "high" as const, notification: { channelId: UPDATES_CHANNEL_ID } },
      apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
    }))
  );

  const dead: string[] = [];
  const failed: string[] = [];
  response.responses.forEach((r, i) => {
    if (r.success) return;
    if (DEAD_TOKEN_CODES.has(r.error?.code ?? "")) dead.push(tokens[i]);
    else failed.push(tokens[i]);
  });
  return { sent: response.successCount, dead, failed };
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
