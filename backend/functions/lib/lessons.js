"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.forceEndLesson = exports.endLesson = exports.startLesson = void 0;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
const https_1 = require("firebase-functions/v2/https");
const tasks_1 = require("firebase-functions/v2/tasks");
const functions_1 = require("firebase-admin/functions");
const firestore_1 = require("firebase-admin/firestore");
const uuid_1 = require("uuid");
const types_1 = require("./types");
const firestore = admin.firestore();
const db = admin.database();
function firstString(...values) {
    for (const value of values) {
        if (typeof value === "string" && value.trim().length > 0) {
            return value;
        }
    }
    return undefined;
}
function sanitizeForFirestore(value) {
    if (value === undefined)
        return null;
    if (Array.isArray(value))
        return value.map((v) => sanitizeForFirestore(v));
    if (value && typeof value === "object") {
        const input = value;
        const output = {};
        for (const [k, v] of Object.entries(input)) {
            output[k] = sanitizeForFirestore(v);
        }
        return output;
    }
    return value;
}
async function resolveQuestionContext(questionId) {
    var _a, _b;
    const questionRef = db.ref(`questions/${questionId}`);
    const questionSnap = await questionRef.once("value");
    if (!questionSnap.exists()) {
        throw new https_1.HttpsError("not-found", "Question not found in RTDB");
    }
    const rtdbQuestion = ((_a = questionSnap.val()) !== null && _a !== void 0 ? _a : {});
    const fsQuestionSnap = await firestore.collection("questions").doc(questionId).get();
    const fsQuestion = ((_b = fsQuestionSnap.data()) !== null && _b !== void 0 ? _b : {});
    const studentUid = firstString(rtdbQuestion.studentUid, rtdbQuestion.studentId, rtdbQuestion.userId, rtdbQuestion.askerUid, fsQuestion.studentUid);
    const teacherUid = firstString(rtdbQuestion.teacherUid, rtdbQuestion.teacherId, rtdbQuestion.teachedId, rtdbQuestion.acceptedByTeacher, rtdbQuestion.tutorUid, rtdbQuestion.responderUid, fsQuestion.acceptedByTeacher, fsQuestion.teacherUid);
    if (!studentUid || !teacherUid) {
        const keys = Object.keys(rtdbQuestion).sort().join(", ") || "none";
        throw new https_1.HttpsError("failed-precondition", `Question is missing participants (RTDB keys: ${keys})`);
    }
    return {
        questionRef,
        rtdbQuestion,
        studentUid,
        teacherUid,
    };
}
async function migrateQuestionToFirestore(questionId, endedBy, context) {
    const { questionRef, rtdbQuestion, studentUid, teacherUid } = context;
    const endedAt = firestore_1.Timestamp.now();
    const migratedQuestion = sanitizeForFirestore(rtdbQuestion);
    const batch = firestore.batch();
    const qDocRef = firestore.collection("questions").doc(questionId);
    batch.set(qDocRef, Object.assign(Object.assign({}, migratedQuestion), { state: "ended", status: "completed", studentUid, acceptedByTeacher: teacherUid, teacherId: teacherUid, teachedId: teacherUid, participants: [studentUid, teacherUid], endedBy,
        endedAt, updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    const studentRef = firestore.collection("users").doc(studentUid);
    const teacherRef = firestore.collection("users").doc(teacherUid);
    batch.set(studentRef, { messagesId: firestore_1.FieldValue.arrayUnion(questionId) }, { merge: true });
    batch.set(teacherRef, { messagesId: firestore_1.FieldValue.arrayUnion(questionId) }, { merge: true });
    await batch.commit();
    await questionRef.remove();
}
// ─── startLesson ──────────────────────────────────────────────────────────────
// FR-B-006, FR-B-010
// Called by either client once the Agora audio channel is connected.
// Creates the /lessons doc and schedules the 30-minute hard-cap task.
exports.startLesson = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const { questionId } = req.data;
    if (!questionId)
        throw new https_1.HttpsError("invalid-argument", "questionId required");
    const qRef = firestore.collection("questions").doc(questionId);
    const qSnap = await qRef.get();
    if (!qSnap.exists)
        throw new https_1.HttpsError("not-found", "Question not found");
    const q = qSnap.data();
    // Guard: only the teacher or student on this question may call startLesson
    if (q.studentUid !== uid && q.acceptedByTeacher !== uid) {
        throw new https_1.HttpsError("permission-denied", "Not a participant in this lesson");
    }
    if (q.status !== "accepted") {
        throw new https_1.HttpsError("failed-precondition", `Cannot start lesson in status: ${q.status}`);
    }
    // Idempotent: if lesson already exists return it
    if (q.lessonId) {
        return { lessonId: q.lessonId };
    }
    const lessonId = (0, uuid_1.v4)();
    const now = new Date();
    const hardCapAt = new Date(now.getTime() + types_1.HARD_CAP_MINUTES * 60 * 1000);
    const agoraTokenSnap = await firestore
        .collection("questions")
        .doc(questionId)
        .get()
        .then((s) => s.data());
    // Retrieve the Agora token from acceptInvite's stored channel
    const liveKitRoom = (_b = agoraTokenSnap.agoraChannel) !== null && _b !== void 0 ? _b : `lesson_${questionId}`;
    const lesson = {
        questionId,
        studentUid: q.studentUid,
        teacherUid: q.acceptedByTeacher,
        startedAt: firestore_1.Timestamp.fromDate(now),
        hardCapAt: firestore_1.Timestamp.fromDate(hardCapAt),
        baseRatePerMinCents: types_1.BASE_RATE_PER_MIN_CENTS,
        connectionFeeCents: types_1.CONNECTION_FEE_CENTS,
        status: "in_progress",
        liveKitRoom,
        liveKitTokenExpiry: firestore_1.Timestamp.fromDate(new Date(now.getTime() + 3600 * 1000)),
    };
    const batch = firestore.batch();
    batch.set(firestore.collection("lessons").doc(lessonId), lesson);
    batch.update(qRef, {
        status: "in_progress",
        startedAt: firestore_1.Timestamp.fromDate(now),
        lessonId,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
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
    const capQueue = (0, functions_1.getFunctions)().taskQueue("forceEndLesson");
    await capQueue.enqueue({ lessonId }, { scheduleDelaySeconds: types_1.HARD_CAP_MINUTES * 60 });
    firebase_functions_1.logger.info(`[lessons] started lessonId=${lessonId} qid=${questionId}`);
    return { lessonId };
});
// ─── endLesson ────────────────────────────────────────────────────────────────
// FR-B-007, FR-B-010
// Called by student or teacher when they tap End.
exports.endLesson = (0, https_1.onCall)(async (req) => {
    var _a;
    const debugContext = { stage: "init" };
    try {
        const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
        if (!uid)
            throw new https_1.HttpsError("unauthenticated", "Sign in required");
        debugContext.uid = uid;
        const { questionId } = req.data;
        if (!questionId)
            throw new https_1.HttpsError("invalid-argument", "questionId required");
        debugContext.questionId = questionId;
        debugContext.stage = "validated-input";
        firebase_functions_1.logger.info(`[lessons] endLesson start qid=${questionId} uid=${uid}`);
        const context = await resolveQuestionContext(questionId);
        debugContext.stage = "loaded-rtdb-question";
        const rtdbKeys = Object.keys(context.rtdbQuestion).sort();
        firebase_functions_1.logger.info(`[lessons] endLesson RTDB question loaded qid=${questionId} keys=${rtdbKeys.join(",") || "none"}`);
        debugContext.stage = "resolved-question-sources";
        debugContext.studentUid = context.studentUid;
        debugContext.teacherUid = context.teacherUid;
        firebase_functions_1.logger.info(`[lessons] endLesson participants resolved qid=${questionId} studentUid=${context.studentUid} teacherUid=${context.teacherUid}`);
        if (uid !== context.studentUid && uid !== context.teacherUid) {
            throw new https_1.HttpsError("permission-denied", "Not a participant in this lesson");
        }
        debugContext.stage = "authorized";
        const endedBy = uid === context.studentUid ? "student" : "teacher";
        debugContext.endedBy = endedBy;
        debugContext.stage = "committing-firestore";
        firebase_functions_1.logger.info(`[lessons] endLesson committing Firestore writes qid=${questionId}`);
        await migrateQuestionToFirestore(questionId, endedBy, context);
        debugContext.stage = "completed";
        firebase_functions_1.logger.info(`[lessons] endLesson migrated qid=${questionId} from RTDB to Firestore and marked ended`);
        return { success: true, questionId, endedBy };
    }
    catch (error) {
        firebase_functions_1.logger.error("[lessons] endLesson failed", { error, debugContext });
        if (error instanceof https_1.HttpsError)
            throw error;
        const message = error instanceof Error ? error.message : String(error);
        throw new https_1.HttpsError("internal", `endLesson failed: ${message}`);
    }
});
// ─── forceEndLesson — Cloud Tasks handler ────────────────────────────────────
// FR-B-006: fires at hardCapAt (30 min after lesson start).
// If the lesson is still in_progress, end it as "system".
exports.forceEndLesson = (0, tasks_1.onTaskDispatched)({
    retryConfig: { maxAttempts: 3 },
    rateLimits: { maxConcurrentDispatches: 20 },
}, async (req) => {
    const { lessonId } = req.data;
    firebase_functions_1.logger.info(`[lessons] forceEndLesson fired lessonId=${lessonId}`);
    if (!lessonId) {
        firebase_functions_1.logger.warn("[lessons] forceEndLesson missing lessonId payload");
        return;
    }
    const lSnap = await firestore.collection("lessons").doc(lessonId).get();
    if (!lSnap.exists) {
        firebase_functions_1.logger.warn(`[lessons] forceEndLesson lesson not found lessonId=${lessonId}`);
        return;
    }
    const lesson = lSnap.data();
    const questionId = lesson.questionId;
    if (!questionId) {
        firebase_functions_1.logger.warn(`[lessons] forceEndLesson lesson missing questionId lessonId=${lessonId}`);
        return;
    }
    const questionSnap = await db.ref(`questions/${questionId}`).once("value");
    if (!questionSnap.exists()) {
        firebase_functions_1.logger.info(`[lessons] forceEndLesson RTDB question already migrated qid=${questionId}`);
        return;
    }
    const context = await resolveQuestionContext(questionId);
    await migrateQuestionToFirestore(questionId, "system", context);
    await firestore.collection("lessons").doc(lessonId).set({
        status: "completed",
        endedBy: "system",
        endedAt: firestore_1.FieldValue.serverTimestamp(),
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    }, { merge: true });
    firebase_functions_1.logger.info(`[lessons] forceEndLesson hard cap applied qid=${questionId} lessonId=${lessonId}`);
});
//# sourceMappingURL=lessons.js.map