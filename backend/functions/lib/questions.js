"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.declineInvite = exports.getQuestionStatus = exports.acceptInvite = exports.cancelQuestion = exports.createQuestion = void 0;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const uuid_1 = require("uuid");
const livekit_1 = require("./livekit");
const fcm_1 = require("./fcm");
const types_1 = require("./types");
const db = admin.database();
const firestore = admin.firestore();
async function upsertLiveQuestion(questionId, patch, status, reason) {
    const payload = Object.assign(Object.assign({}, patch), { status, updatedAt: Date.now() });
    firebase_functions_1.logger.info(`[questions] upsertLiveQuestion start qid=${questionId} status=${status} reason=${reason} keys=${Object.keys(payload).sort().join(",")}`);
    await db.ref(`questions/${questionId}`).update(payload);
    firebase_functions_1.logger.info(`[questions] upsertLiveQuestion done qid=${questionId} status=${status} reason=${reason}`);
}
async function cleanupRtdb(questionId, alreadyInvited) {
    firebase_functions_1.logger.info(`[questions] cleanupRtdb start qid=${questionId} invitesToClear=${alreadyInvited.length}`);
    const questionRef = db.ref(`questions/${questionId}`);
    const questionExists = (await questionRef.once("value")).exists();
    firebase_functions_1.logger.info(`[questions] cleanupRtdb precheck qid=${questionId} rtdbQuestionExists=${questionExists}`);
    await Promise.all([
        questionRef.remove(),
        ...alreadyInvited.map((tid) => db.ref(`teacherInvites/${tid}/${questionId}`).remove()),
    ]);
    firebase_functions_1.logger.info(`[questions] cleanupRtdb done qid=${questionId} removedQuestion=${questionExists} removedTeacherInvites=${alreadyInvited.length}`);
}
// ─── createQuestion ───────────────────────────────────────────────────────────
// FR-B-010: callable — student initiates the question + dispatch pipeline.
// Writing the Firestore doc triggers dispatchQuestion automatically.
exports.createQuestion = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const { topic, text, photoUrls = [], voiceMemoUrl, conversationType: rawConversationType, } = req.data;
    const conversationType = types_1.CONVERSATION_TYPES.includes(rawConversationType)
        ? rawConversationType
        : types_1.DEFAULT_CONVERSATION_TYPE;
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
    firebase_functions_1.logger.info(`[questions] createQuestion start qid=${qid} student=${uid} topic=${topic} conversationType=${conversationType}`);
    const question = Object.assign(Object.assign({ studentUid: uid, topic, text: text.trim(), photoUrls }, (voiceMemoUrl ? { voiceMemoUrl } : {})), { conversationType, status: "searching", createdAt: firestore_1.Timestamp.now(), updatedAt: firestore_1.Timestamp.now(), dispatchWave: 0, alreadyInvited: [] });
    const liveQuestion = Object.assign(Object.assign({ questionId: qid, studentUid: uid, topic, text: text.trim(), photoUrls }, (voiceMemoUrl ? { voiceMemoUrl } : {})), { conversationType, dispatchWave: 0, createdAt: Date.now() });
    await upsertLiveQuestion(qid, liveQuestion, "searching", "createQuestion");
    firebase_functions_1.logger.info(`[questions] createQuestion RTDB-upsert done qid=${qid}`);
    // Writing this doc triggers dispatchQuestion via the Firestore onCreate trigger.
    await firestore.collection("questions").doc(qid).set(question);
    firebase_functions_1.logger.info(`[questions] createQuestion firestore-set done qid=${qid} status=${question.status} dispatchWave=${question.dispatchWave}`);
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
    firebase_functions_1.logger.info(`[questions] cancelQuestion requested qid=${questionId} by student=${uid}`);
    const qRef = firestore.collection("questions").doc(questionId);
    let alreadyInvited = [];
    await firestore.runTransaction(async (tx) => {
        var _a, _b;
        const snap = await tx.get(qRef);
        if (!snap.exists)
            throw new https_1.HttpsError("not-found", "Question not found");
        const data = snap.data();
        firebase_functions_1.logger.info(`[questions] cancelQuestion tx-read qid=${questionId} status=${data.status} alreadyInvited=${((_a = data.alreadyInvited) !== null && _a !== void 0 ? _a : []).length}`);
        if (data.studentUid !== uid)
            throw new https_1.HttpsError("permission-denied", "Not your question");
        const cancellable = ["searching", "accepted"];
        if (!cancellable.includes(data.status)) {
            throw new https_1.HttpsError("failed-precondition", `Cannot cancel a question with status: ${data.status}`);
        }
        alreadyInvited = (_b = data.alreadyInvited) !== null && _b !== void 0 ? _b : [];
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
    var _a, _b, _c, _d, _e, _f, _g, _h, _j;
    const teacherUid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!teacherUid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const { questionId } = req.data;
    if (!questionId)
        throw new https_1.HttpsError("invalid-argument", "questionId required");
    firebase_functions_1.logger.info(`[questions] acceptInvite requested qid=${questionId} by teacher=${teacherUid}`);
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
        firebase_functions_1.logger.info(`[questions] acceptInvite tx-read qid=${questionId} questionStatus=${q.status} inviteResponse=${inv.response} inviteWave=${inv.wave}`);
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
    await upsertLiveQuestion(questionId, {
        studentUid,
        teacherUid,
        teacherId: teacherUid,
        acceptedByTeacher: teacherUid,
        acceptedAt: Date.now(),
    }, "accepted", "acceptInvite");
    // Mint LiveKit tokens for both parties
    const channelName = `lesson_${questionId}`;
    const [teacherToken, studentToken] = await Promise.all([
        (0, livekit_1.mintLiveKitToken)(channelName, teacherUid),
        (0, livekit_1.mintLiveKitToken)(channelName, studentUid),
    ]);
    // Snapshot both participants' name+image so lesson history can render without
    // cross-user reads (Firestore rules block students from reading teacher docs
    // and vice versa). These fields are frozen at accept-time on purpose.
    const [teacherRecord, studentFcmToken, teacherUserSnap, studentUserSnap] = await Promise.all([
        db.ref(`teachers/${teacherUid}`).once("value").then((s) => s.val()),
        db.ref(`users/${studentUid}/fcmToken`).once("value").then((s) => s.val()),
        firestore.collection("users").doc(teacherUid).get(),
        firestore.collection("users").doc(studentUid).get(),
    ]);
    const teacherUser = (_b = teacherUserSnap.data()) !== null && _b !== void 0 ? _b : {};
    const studentUser = (_c = studentUserSnap.data()) !== null && _c !== void 0 ? _c : {};
    const pickImage = (u) => {
        var _a, _b, _c;
        return (_c = (_b = (_a = u.profileImageURL) !== null && _a !== void 0 ? _a : u.profilePhotoURL) !== null && _b !== void 0 ? _b : u.photoURL) !== null && _c !== void 0 ? _c : "";
    };
    if (studentFcmToken) {
        await (0, fcm_1.sendAcceptedPush)({
            fcmToken: studentFcmToken,
            teacherName: (_d = teacherRecord === null || teacherRecord === void 0 ? void 0 : teacherRecord.displayName) !== null && _d !== void 0 ? _d : "Your teacher",
            questionId,
            agoraChannel: channelName,
            agoraToken: studentToken.token,
            agoraUid: 0,
        });
    }
    // Store the LiveKit room name + name/image snapshots on the question doc.
    await qRef.update({
        agoraChannel: channelName,
        teacherName: (_e = teacherUser.fullName) !== null && _e !== void 0 ? _e : "",
        teacherImageURL: pickImage(teacherUser),
        studentName: (_f = studentUser.fullName) !== null && _f !== void 0 ? _f : "",
        studentImageURL: pickImage(studentUser),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    await upsertLiveQuestion(questionId, {
        agoraChannel: channelName,
        teacherName: (_g = teacherUser.fullName) !== null && _g !== void 0 ? _g : "",
        teacherImageURL: pickImage(teacherUser),
        studentName: (_h = studentUser.fullName) !== null && _h !== void 0 ? _h : "",
        studentImageURL: pickImage(studentUser),
    }, "accepted", "acceptInvite-profile-sync");
    // Clear RTDB invite signals for ALL teachers who were invited — question is taken
    const qSnap = await qRef.get();
    const alreadyInvited = (_j = qSnap.data().alreadyInvited) !== null && _j !== void 0 ? _j : [];
    firebase_functions_1.logger.info(`[questions] acceptInvite clearing teacher RTDB invites qid=${questionId} invitedCount=${alreadyInvited.length}`);
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
    firebase_functions_1.logger.info(`[questions] getQuestionStatus qid=${questionId} student=${uid} status=${q.status}`);
    if (q.status === "accepted" || q.status === "in_progress") {
        const roomName = `lesson_${questionId}`;
        const token = await (0, livekit_1.mintLiveKitToken)(roomName, uid);
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
    firebase_functions_1.logger.info(`[questions] declineInvite requested qid=${questionId} by teacher=${teacherUid}`);
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