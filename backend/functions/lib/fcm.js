"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.sendInvitePush = sendInvitePush;
exports.sendAcceptedPush = sendAcceptedPush;
exports.sendNoMatchPush = sendNoMatchPush;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
// Teacher invite — data-only, high priority, TTL matches the wave timeout.
// The client renders a full-screen incoming-call UI from these fields.
async function sendInvitePush(params) {
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
    }).catch((err) => firebase_functions_1.logger.warn(`FCM invite failed for token ${fcmToken}:`, err));
}
// Notify student that their question was accepted.
async function sendAcceptedPush(params) {
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
    }).catch((err) => firebase_functions_1.logger.warn(`FCM accepted push failed for token ${fcmToken}:`, err));
}
// Notify student that no teacher was found.
async function sendNoMatchPush(params) {
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
    }).catch((err) => firebase_functions_1.logger.warn(`FCM no-match push failed for token ${fcmToken}:`, err));
}
//# sourceMappingURL=fcm.js.map