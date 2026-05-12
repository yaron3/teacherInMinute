"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.evaluateWave = exports.dispatchQuestion = void 0;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
const firestore_1 = require("firebase-functions/v2/firestore");
const tasks_1 = require("firebase-functions/v2/tasks");
const functions_1 = require("firebase-admin/functions");
const firestore_2 = require("firebase-admin/firestore");
const scoring_1 = require("./scoring");
const fcm_1 = require("./fcm");
const types_1 = require("./types");
const db = admin.database();
const firestore = admin.firestore();
// ─── helpers ─────────────────────────────────────────────────────────────────
async function allTeachers() {
    var _a;
    const snap = await db.ref("teachers").once("value");
    return (_a = snap.val()) !== null && _a !== void 0 ? _a : {};
}
async function sendWave(qid, questionData, wave, exclude) {
    const teachers = await allTeachers();
    const ranked = (0, scoring_1.rankTeachers)(teachers, questionData.topic, exclude);
    const waveSize = types_1.WAVE_SIZES[wave - 1];
    const batch = ranked.slice(0, waveSize);
    if (batch.length === 0)
        return [];
    const now = firestore_2.Timestamp.now();
    const expiresAt = firestore_2.Timestamp.fromMillis(Date.now() + types_1.WAVE_TIMEOUT_SECONDS * 1000);
    const firestoreBatch = firestore.batch();
    for (const { uid } of batch) {
        const inviteRef = firestore
            .collection("questions")
            .doc(qid)
            .collection("invites")
            .doc(uid);
        const invite = {
            teacherUid: uid,
            questionId: qid,
            sentAt: now,
            expiresAt,
            response: "pending",
            wave,
        };
        firestoreBatch.set(inviteRef, invite);
    }
    await firestoreBatch.commit();
    // RTDB signals — the app listens to teacherInvites/{uid}/{qid} for real-time invite delivery.
    // Written in parallel with FCM so the app catches invites even without a push token.
    const teacherRecords = await allTeachers();
    await Promise.all(batch.map(async ({ uid }) => {
        await db.ref(`teacherInvites/${uid}/${qid}`).set({
            topic: questionData.topic,
            text: questionData.text.slice(0, 300),
            expiresAt: Date.now() + types_1.WAVE_TIMEOUT_SECONDS * 1000,
            wave,
        });
        // FCM on top of RTDB — best-effort, no-op if no token
        const t = teacherRecords[uid];
        if (t === null || t === void 0 ? void 0 : t.fcmToken) {
            await (0, fcm_1.sendInvitePush)({
                fcmToken: t.fcmToken,
                questionId: qid,
                topic: questionData.topic,
                studentName: questionData.studentUid,
                questionText: questionData.text,
                wave,
                ttlSeconds: types_1.WAVE_TIMEOUT_SECONDS,
            });
        }
    }));
    firebase_functions_1.logger.info(`[dispatch] wave=${wave} qid=${qid} sent to ${batch.length} teachers`);
    return batch.map((t) => t.uid);
}
async function enqueueWaveEvaluation(qid, wave) {
    const queue = (0, functions_1.getFunctions)().taskQueue("evaluateWave");
    await queue.enqueue({ questionId: qid, wave }, { scheduleDelaySeconds: types_1.WAVE_TIMEOUT_SECONDS });
}
// ─── dispatchQuestion — Firestore onCreate trigger ───────────────────────────
// FR-B-001, FR-B-002, FR-B-003
exports.dispatchQuestion = (0, firestore_1.onDocumentCreated)("questions/{qid}", async (event) => {
    var _a;
    const qid = event.params.qid;
    const data = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    if (!data) {
        firebase_functions_1.logger.error(`[dispatch] no data for qid=${qid}`);
        return;
    }
    if (data.status !== "searching") {
        firebase_functions_1.logger.info(`[dispatch] skipping qid=${qid} status=${data.status}`);
        return;
    }
    firebase_functions_1.logger.info(`[dispatch] starting dispatch for qid=${qid} topic=${data.topic}`);
    const invited = await sendWave(qid, data, 1, new Set());
    if (invited.length === 0) {
        // No eligible teachers at all — declare unanswered immediately
        await firestore.collection("questions").doc(qid).update({
            status: "unanswered",
            updatedAt: firestore_2.FieldValue.serverTimestamp(),
        });
        // Notify student if we have their FCM token
        firebase_functions_1.logger.info(`[dispatch] no teachers found for qid=${qid}, declared unanswered`);
        return;
    }
    await firestore.collection("questions").doc(qid).update({
        dispatchWave: 1,
        alreadyInvited: firestore_2.FieldValue.arrayUnion(...invited),
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    });
    await enqueueWaveEvaluation(qid, 1);
});
// ─── evaluateWave — Cloud Tasks handler ──────────────────────────────────────
// FR-B-003, FR-B-005
// Called 12s after each wave is sent. If no teacher accepted, fans out next wave
// or declares the question unanswered after wave 3.
exports.evaluateWave = (0, tasks_1.onTaskDispatched)({
    retryConfig: { maxAttempts: 1 },
    rateLimits: { maxConcurrentDispatches: 50 },
}, async (req) => {
    var _a;
    const { questionId: qid, wave } = req.data;
    const qRef = firestore.collection("questions").doc(qid);
    const qSnap = await qRef.get();
    if (!qSnap.exists) {
        firebase_functions_1.logger.warn(`[evaluateWave] qid=${qid} not found`);
        return;
    }
    const data = qSnap.data();
    if (data.status !== "searching") {
        firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} already ${data.status}, skipping wave=${wave}`);
        return;
    }
    // Mark all pending invites from this wave as timed out
    const invitesSnap = await firestore
        .collection("questions")
        .doc(qid)
        .collection("invites")
        .where("wave", "==", wave)
        .where("response", "==", "pending")
        .get();
    if (!invitesSnap.empty) {
        const timeoutBatch = firestore.batch();
        invitesSnap.docs.forEach((d) => timeoutBatch.update(d.ref, { response: "timeout" }));
        await timeoutBatch.commit();
        // Remove RTDB signals for timed-out teachers
        await Promise.all(invitesSnap.docs.map((d) => {
            const tid = d.data().teacherUid;
            return db.ref(`teacherInvites/${tid}/${qid}`).remove();
        }));
        firebase_functions_1.logger.info(`[evaluateWave] timed out ${invitesSnap.size} invites for wave=${wave} qid=${qid}`);
    }
    const nextWave = wave + 1;
    // FR-B-005: after wave 3 with no acceptance, declare unanswered
    if (nextWave > types_1.WAVE_SIZES.length) {
        await qRef.update({
            status: "unanswered",
            updatedAt: firestore_2.FieldValue.serverTimestamp(),
        });
        firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} declared unanswered after wave ${wave}`);
        // Notify student
        const studentFcmToken = await db
            .ref(`users/${data.studentUid}/fcmToken`)
            .once("value")
            .then((s) => s.val());
        if (studentFcmToken) {
            await (0, fcm_1.sendNoMatchPush)({ fcmToken: studentFcmToken, questionId: qid });
        }
        return;
    }
    // Fan out next wave
    const alreadyInvited = new Set((_a = data.alreadyInvited) !== null && _a !== void 0 ? _a : []);
    const invited = await sendWave(qid, data, nextWave, alreadyInvited);
    if (invited.length === 0) {
        // Ran out of eligible teachers mid-dispatch
        await qRef.update({
            status: "unanswered",
            updatedAt: firestore_2.FieldValue.serverTimestamp(),
        });
        firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} no teachers for wave=${nextWave}, unanswered`);
        return;
    }
    await qRef.update({
        dispatchWave: nextWave,
        alreadyInvited: firestore_2.FieldValue.arrayUnion(...invited),
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    });
    await enqueueWaveEvaluation(qid, nextWave);
    firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} wave=${nextWave} enqueued`);
});
//# sourceMappingURL=dispatch.js.map