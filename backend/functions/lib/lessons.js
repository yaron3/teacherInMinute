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
// ─── billing helpers ──────────────────────────────────────────────────────────
// FR-B-007: round raw seconds up to the next ROUND_UP_SECONDS boundary.
function billableSeconds(startedAt, endedAt) {
    const rawSeconds = Math.floor((endedAt.getTime() - startedAt.getTime()) / 1000);
    if (rawSeconds < types_1.MIN_BILLABLE_SECONDS)
        return 0;
    return Math.ceil(rawSeconds / types_1.ROUND_UP_SECONDS) * types_1.ROUND_UP_SECONDS;
}
function totalCents(billedSecs) {
    return types_1.CONNECTION_FEE_CENTS + Math.ceil((billedSecs / 60) * types_1.BASE_RATE_PER_MIN_CENTS);
}
async function finaliseLesson(lessonId, endedBy) {
    const lRef = firestore.collection("lessons").doc(lessonId);
    // Fetch messages before the transaction — read-only, no consistency required
    const messagesSnap = await firestore
        .collection("lessons")
        .doc(lessonId)
        .collection("messages")
        .orderBy("sentAt")
        .get();
    const messages = messagesSnap.docs.map((d) => d.data());
    return firestore.runTransaction(async (tx) => {
        var _a, _b;
        const snap = await tx.get(lRef);
        if (!snap.exists)
            throw new https_1.HttpsError("not-found", "Lesson not found");
        const lesson = snap.data();
        if (lesson.status !== "in_progress") {
            // Idempotent — already ended (e.g. both sides hit End within 2s)
            return {
                billedSeconds: (_a = lesson.billedSeconds) !== null && _a !== void 0 ? _a : 0,
                totalCents: (_b = lesson.totalCents) !== null && _b !== void 0 ? _b : types_1.CONNECTION_FEE_CENTS,
            };
        }
        const endedAt = new Date();
        const billed = billableSeconds(lesson.startedAt.toDate(), endedAt);
        const charged = totalCents(billed);
        tx.update(lRef, {
            status: "completed",
            endedAt: firestore_1.Timestamp.fromDate(endedAt),
            billedSeconds: billed,
            totalCents: charged,
            endedBy,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        // Mirror summary + session snapshot to the question doc
        const qRef = firestore.collection("questions").doc(lesson.questionId);
        tx.update(qRef, {
            status: "completed",
            endedAt: firestore_1.Timestamp.fromDate(endedAt),
            billedSeconds: billed,
            totalCents: charged,
            endedBy,
            participants: [lesson.studentUid, lesson.teacherUid],
            startTime: lesson.startedAt,
            endTime: firestore_1.Timestamp.fromDate(endedAt),
            messages,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        // Append questionId to history for both participants
        const studentRef = firestore.collection("users").doc(lesson.studentUid);
        const teacherRef = firestore.collection("users").doc(lesson.teacherUid);
        tx.set(studentRef, { history: firestore_1.FieldValue.arrayUnion(lesson.questionId) }, { merge: true });
        tx.set(teacherRef, { history: firestore_1.FieldValue.arrayUnion(lesson.questionId) }, { merge: true });
        firebase_functions_1.logger.info(`[lessons] finalised lessonId=${lessonId} billed=${billed}s total=${charged}¢ by=${endedBy}`);
        return { billedSeconds: billed, totalCents: charged };
    });
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
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const { lessonId } = req.data;
    if (!lessonId)
        throw new https_1.HttpsError("invalid-argument", "lessonId required");
    const lSnap = await firestore.collection("lessons").doc(lessonId).get();
    if (!lSnap.exists)
        throw new https_1.HttpsError("not-found", "Lesson not found");
    const lesson = lSnap.data();
    if (lesson.studentUid !== uid && lesson.teacherUid !== uid) {
        throw new https_1.HttpsError("permission-denied", "Not a participant in this lesson");
    }
    const endedBy = uid === lesson.studentUid ? "student" : "teacher";
    const result = await finaliseLesson(lessonId, endedBy);
    return result;
});
// ─── forceEndLesson — Cloud Tasks handler ────────────────────────────────────
// FR-B-006: fires at hardCapAt (30 min after lesson start).
// If the lesson is still in_progress, end it as "system".
exports.forceEndLesson = (0, tasks_1.onTaskDispatched)({
    retryConfig: { maxAttempts: 3 },
    rateLimits: { maxConcurrentDispatches: 20 },
}, async (req) => {
    const { lessonId } = req.data;
    firebase_functions_1.logger.info(`[lessons] forceEndLesson fired for lessonId=${lessonId}`);
    const lSnap = await firestore.collection("lessons").doc(lessonId).get();
    if (!lSnap.exists) {
        firebase_functions_1.logger.warn(`[lessons] forceEndLesson: lessonId=${lessonId} not found`);
        return;
    }
    const lesson = lSnap.data();
    if (lesson.status !== "in_progress") {
        firebase_functions_1.logger.info(`[lessons] forceEndLesson: lessonId=${lessonId} already ${lesson.status}`);
        return;
    }
    await finaliseLesson(lessonId, "system");
    firebase_functions_1.logger.info(`[lessons] forceEndLesson: hard cap applied lessonId=${lessonId}`);
});
//# sourceMappingURL=lessons.js.map