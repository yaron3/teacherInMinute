"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.declineInvite = exports.getQuestionStatus = exports.acceptInvite = exports.cancelQuestion = exports.createQuestion = void 0;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const uuid_1 = require("uuid");
const agora_1 = require("./agora");
const fcm_1 = require("./fcm");
const types_1 = require("./types");
const db = admin.database();
const firestore = admin.firestore();
async function cleanupRtdb(questionId, alreadyInvited) {
    await Promise.all([
        db.ref(`questions/${questionId}`).remove(),
        ...alreadyInvited.map((tid) => db.ref(`teacherInvites/${tid}/${questionId}`).remove()),
    ]);
}
// ─── createQuestion ───────────────────────────────────────────────────────────
// FR-B-010: callable — student initiates the question + dispatch pipeline.
// Writing the Firestore doc triggers dispatchQuestion automatically.
exports.createQuestion = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const { topic, text, photoUrls = [], voiceMemoUrl } = req.data;
    if (!topic || !(text === null || text === void 0 ? void 0 : text.trim())) {
        throw new https_1.HttpsError("invalid-argument", "topic and text are required");
    }
    const validTopics = ["algebra", "geometry", "trigonometry", "calculus", "statistics", "arithmetic"];
    if (!validTopics.includes(topic)) {
        throw new https_1.HttpsError("invalid-argument", `topic must be one of: ${validTopics.join(", ")}`);
    }
    if (text.trim().length < 10) {
        throw new https_1.HttpsError("invalid-argument", "Question text must be at least 10 characters");
    }
    const studentSnap = await firestore.collection("users").doc(uid).get();
    const remainingMinutes = (_c = (_b = studentSnap.data()) === null || _b === void 0 ? void 0 : _b.remainingMinutes) !== null && _c !== void 0 ? _c : 0;
    if (remainingMinutes < 2) {
        throw new https_1.HttpsError("resource-exhausted", "Not enough time left");
    }
    const qid = (0, uuid_1.v4)();
    const question = Object.assign(Object.assign({ studentUid: uid, topic, text: text.trim(), photoUrls }, (voiceMemoUrl ? { voiceMemoUrl } : {})), { status: "searching", createdAt: firestore_1.Timestamp.now(), updatedAt: firestore_1.Timestamp.now(), dispatchWave: 0, alreadyInvited: [] });
    // Writing this doc triggers dispatchQuestion via the Firestore onCreate trigger.
    await firestore.collection("questions").doc(qid).set(question);
    firebase_functions_1.logger.info(`[questions] created qid=${qid} topic=${topic} student=${uid}`);
    return { questionId: qid, connectionFeeCents: types_1.CONNECTION_FEE_CENTS };
});
// ─── cancelQuestion ───────────────────────────────────────────────────────────
// FR-B-010: student cancels while still in "searching" state. Free before a
// teacher has accepted. We do not charge for pilot (no Stripe hold).
exports.cancelQuestion = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const { questionId } = req.data;
    if (!questionId)
        throw new https_1.HttpsError("invalid-argument", "questionId required");
    const qRef = firestore.collection("questions").doc(questionId);
    let alreadyInvited = [];
    await firestore.runTransaction(async (tx) => {
        var _a;
        const snap = await tx.get(qRef);
        if (!snap.exists)
            throw new https_1.HttpsError("not-found", "Question not found");
        const data = snap.data();
        if (data.studentUid !== uid)
            throw new https_1.HttpsError("permission-denied", "Not your question");
        const cancellable = ["searching", "accepted"];
        if (!cancellable.includes(data.status)) {
            throw new https_1.HttpsError("failed-precondition", `Cannot cancel a question with status: ${data.status}`);
        }
        alreadyInvited = (_a = data.alreadyInvited) !== null && _a !== void 0 ? _a : [];
        tx.update(qRef, {
            status: "cancelled",
            endedBy: "student",
            endedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    });
    await cleanupRtdb(questionId, alreadyInvited);
    firebase_functions_1.logger.info(`[questions] cancelled qid=${questionId} by student=${uid}`);
    return { success: true };
});
// ─── acceptInvite ─────────────────────────────────────────────────────────────
// FR-B-004: atomic Firestore transaction guarantees exactly one teacher wins.
// Returns Agora token for the teacher; pushes token to student via FCM.
exports.acceptInvite = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    const teacherUid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!teacherUid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const { questionId } = req.data;
    if (!questionId)
        throw new https_1.HttpsError("invalid-argument", "questionId required");
    const qRef = firestore.collection("questions").doc(questionId);
    const inviteRef = qRef.collection("invites").doc(teacherUid);
    let studentUid = "";
    // Atomic claim — only one teacher can win
    await firestore.runTransaction(async (tx) => {
        const [qSnap, invSnap] = await Promise.all([tx.get(qRef), tx.get(inviteRef)]);
        if (!qSnap.exists)
            throw new https_1.HttpsError("not-found", "Question not found");
        if (!invSnap.exists)
            throw new https_1.HttpsError("not-found", "Invite not found");
        const q = qSnap.data();
        const inv = invSnap.data();
        // FR-B-004: fail only if someone else already claimed it.
        // "unanswered" means all waves timed out but no one accepted — a teacher with
        // a still-valid invite (INVITE_EXPIRY_SECONDS > WAVE_TIMEOUT_SECONDS * waves)
        // can still legitimately accept it.
        if (q.status === "accepted" || q.status === "in_progress" || q.status === "completed") {
            throw new https_1.HttpsError("already-exists", "Question already claimed by another teacher");
        }
        if (q.status === "cancelled") {
            throw new https_1.HttpsError("failed-precondition", "Question was cancelled by the student");
        }
        if (q.status !== "searching" && q.status !== "unanswered") {
            throw new https_1.HttpsError("failed-precondition", `Question is not available (status: ${q.status})`);
        }
        if (inv.response !== "pending") {
            throw new https_1.HttpsError("failed-precondition", "Invite is no longer pending");
        }
        // Check invite hasn't expired
        if (inv.expiresAt.toMillis() < Date.now()) {
            throw new https_1.HttpsError("deadline-exceeded", "Invite has expired");
        }
        studentUid = q.studentUid;
        tx.update(qRef, {
            status: "accepted",
            acceptedByTeacher: teacherUid,
            acceptedAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        tx.update(inviteRef, { response: "accept" });
    });
    // Mint LiveKit tokens for both parties
    const channelName = `lesson_${questionId}`;
    const [teacherToken, studentToken] = await Promise.all([
        (0, agora_1.mintLiveKitToken)(channelName, teacherUid),
        (0, agora_1.mintLiveKitToken)(channelName, studentUid),
    ]);
    // Push the student's token to them via FCM
    const [teacherRecord, studentFcmToken] = await Promise.all([
        db.ref(`teachers/${teacherUid}`).once("value").then((s) => s.val()),
        db.ref(`users/${studentUid}/fcmToken`).once("value").then((s) => s.val()),
    ]);
    if (studentFcmToken) {
        await (0, fcm_1.sendAcceptedPush)({
            fcmToken: studentFcmToken,
            teacherName: (_b = teacherRecord === null || teacherRecord === void 0 ? void 0 : teacherRecord.displayName) !== null && _b !== void 0 ? _b : "Your teacher",
            questionId,
            agoraChannel: channelName,
            agoraToken: studentToken.token,
            agoraUid: 0,
        });
    }
    // Store the LiveKit room name on the question for startLesson to use
    await qRef.update({
        agoraChannel: channelName,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    // Clear RTDB invite signals for ALL teachers who were invited — question is taken
    const qSnap = await qRef.get();
    const alreadyInvited = (_c = qSnap.data().alreadyInvited) !== null && _c !== void 0 ? _c : [];
    await Promise.all(alreadyInvited.map((uid) => db.ref(`teacherInvites/${uid}/${questionId}`).remove()));
    firebase_functions_1.logger.info(`[questions] accepted qid=${questionId} teacher=${teacherUid}`);
    return {
        liveKitRoom: channelName,
        liveKitToken: teacherToken.token,
        studentUid,
    };
});
// ─── getQuestionStatus ────────────────────────────────────────────────────────
// Polled by the student app every 3s while in "searching" state.
// Returns {status} plus LiveKit credentials if the question was accepted.
exports.getQuestionStatus = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const { questionId } = req.data;
    if (!questionId)
        throw new https_1.HttpsError("invalid-argument", "questionId required");
    const qSnap = await firestore.collection("questions").doc(questionId).get();
    if (!qSnap.exists)
        throw new https_1.HttpsError("not-found", "Question not found");
    const q = qSnap.data();
    if (q.studentUid !== uid)
        throw new https_1.HttpsError("permission-denied", "Not your question");
    if (q.status === "accepted" || q.status === "in_progress") {
        const roomName = `lesson_${questionId}`;
        const token = await (0, agora_1.mintLiveKitToken)(roomName, uid);
        return { status: q.status, liveKitRoom: roomName, liveKitToken: token.token };
    }
    return { status: q.status };
});
// ─── declineInvite ────────────────────────────────────────────────────────────
// FR-B-010: teacher explicitly declines. Updates invite; accept_rate signal
// is recomputed by a scheduled function (deferred for pilot).
exports.declineInvite = (0, https_1.onCall)(async (req) => {
    var _a;
    const teacherUid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!teacherUid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const { questionId } = req.data;
    if (!questionId)
        throw new https_1.HttpsError("invalid-argument", "questionId required");
    const inviteRef = firestore
        .collection("questions")
        .doc(questionId)
        .collection("invites")
        .doc(teacherUid);
    const snap = await inviteRef.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Invite not found");
    const inv = snap.data();
    if (inv.response !== "pending") {
        throw new https_1.HttpsError("failed-precondition", "Invite already responded to");
    }
    await inviteRef.update({ response: "decline" });
    // Remove RTDB signal for this teacher only — others still have their invite
    await db.ref(`teacherInvites/${teacherUid}/${questionId}`).remove();
    firebase_functions_1.logger.info(`[questions] declined qid=${questionId} teacher=${teacherUid}`);
    return { success: true };
});
//# sourceMappingURL=questions.js.map