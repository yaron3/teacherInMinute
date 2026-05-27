"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.forceEndLesson = exports.rateTeacher = exports.endLesson = exports.startLesson = void 0;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
const https_1 = require("firebase-functions/v2/https");
const tasks_1 = require("firebase-functions/v2/tasks");
const functions_1 = require("firebase-admin/functions");
const firestore_1 = require("firebase-admin/firestore");
const uuid_1 = require("uuid");
const types_1 = require("./types");
const billing_1 = require("./billing");
const dispatch_1 = require("./dispatch");
const pricing_1 = require("./pricing");
const firestore = admin.firestore();
const db = admin.database();
function toTimestamp(value) {
    if (value instanceof firestore_1.Timestamp)
        return value;
    if (value instanceof Date)
        return firestore_1.Timestamp.fromDate(value);
    if (typeof value === "number" && Number.isFinite(value)) {
        return firestore_1.Timestamp.fromMillis(value);
    }
    if (typeof value === "object" &&
        value !== null &&
        typeof value.toMillis === "function") {
        try {
            const millis = Number(value.toMillis());
            if (Number.isFinite(millis))
                return firestore_1.Timestamp.fromMillis(millis);
        }
        catch (_a) {
            // ignore invalid timestamp-like values
        }
    }
    return undefined;
}
function firstString(...values) {
    for (const value of values) {
        if (typeof value === "string" && value.trim().length > 0) {
            return value;
        }
    }
    return undefined;
}
function firstNumber(...values) {
    for (const value of values) {
        if (typeof value === "number" && Number.isFinite(value)) {
            return value;
        }
    }
    return undefined;
}
function toMillis(value) {
    if (typeof value === "number" && Number.isFinite(value)) {
        // Heuristic: treat small epochs as seconds.
        return value < 1e12 ? value * 1000 : value;
    }
    if (typeof value === "string") {
        const parsed = Number(value);
        return Number.isFinite(parsed) ? (parsed < 1e12 ? parsed * 1000 : parsed) : undefined;
    }
    if (!value || typeof value !== "object")
        return undefined;
    const obj = value;
    if (typeof obj.toMillis === "function") {
        const ms = obj.toMillis();
        return Number.isFinite(ms) ? ms : undefined;
    }
    if (typeof obj.seconds === "number") {
        return obj.seconds * 1000;
    }
    if (typeof obj._seconds === "number") {
        return obj._seconds * 1000;
    }
    if (typeof obj.milliseconds === "number") {
        return obj.milliseconds;
    }
    if (typeof obj.ms === "number") {
        return obj.ms;
    }
    return undefined;
}
function readStampedPricing(lesson) {
    if (!lesson)
        return undefined;
    const currency = typeof lesson.currencyCode === "string" ? lesson.currencyCode.trim().toUpperCase() : "";
    const pricePerMinute = Number(lesson.pricePerMinute);
    const teacherShare = Number(lesson.teacherShare);
    const exchangeRate = Number(lesson.exchangeRateToUsd);
    if (currency.length === 3 &&
        Number.isFinite(pricePerMinute) && pricePerMinute > 0 &&
        Number.isFinite(teacherShare) && teacherShare > 0 && teacherShare <= 1 &&
        Number.isFinite(exchangeRate) && exchangeRate > 0) {
        return { currencyCode: currency, pricePerMinute, teacherShare, exchangeRateToUsd: exchangeRate };
    }
    return undefined;
}
async function resolveLessonPricing(studentUid, lesson) {
    const stamped = readStampedPricing(lesson);
    if (stamped)
        return stamped;
    const resolved = await (0, pricing_1.resolvePricingForStudent)(studentUid);
    return {
        currencyCode: resolved.currency,
        pricePerMinute: resolved.pricePerMinute,
        teacherShare: resolved.teacherShare,
        exchangeRateToUsd: resolved.exchangeRateToUsd,
    };
}
async function loadLessonDocByQuestionId(questionId) {
    const snap = await firestore
        .collection("lessons")
        .where("questionId", "==", questionId)
        .limit(1)
        .get();
    if (snap.empty)
        return undefined;
    const doc = snap.docs[0];
    return { ref: doc.ref, data: doc.data() };
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
    const acceptedAtMs = firstNumber(toMillis(rtdbQuestion.acceptedAt), toMillis(fsQuestion.acceptedAt));
    // Billing starts from when both parties were fully connected (startLesson),
    // not from when the teacher accepted the invite.
    const startedAtMs = firstNumber(toMillis(rtdbQuestion.startedAt), toMillis(fsQuestion.startedAt));
    const studentUid = firstString(rtdbQuestion.studentUid, rtdbQuestion.studentId, rtdbQuestion.userId, rtdbQuestion.askerUid, fsQuestion.studentUid);
    const teacherUid = firstString(rtdbQuestion.teacherUid, rtdbQuestion.teacherId, rtdbQuestion.acceptedByTeacher, rtdbQuestion.tutorUid, rtdbQuestion.responderUid, fsQuestion.acceptedByTeacher, fsQuestion.teacherUid);
    if (!studentUid || !teacherUid) {
        const keys = Object.keys(rtdbQuestion).sort().join(", ") || "none";
        throw new https_1.HttpsError("failed-precondition", `Question is missing participants (RTDB keys: ${keys})`);
    }
    if (!acceptedAtMs) {
        throw new https_1.HttpsError("failed-precondition", "Question is missing acceptedAt");
    }
    return {
        questionRef,
        rtdbQuestion,
        studentUid,
        teacherUid,
        acceptedAtMs,
        startedAtMs,
    };
}
async function migrateQuestionToFirestore(questionId, endedBy, context) {
    var _a;
    const { questionRef, rtdbQuestion, studentUid, teacherUid, startedAtMs } = context;
    firebase_functions_1.logger.info(`[lessons] migrateQuestionToFirestore start qid=${questionId} endedBy=${endedBy} studentUid=${studentUid} teacherUid=${teacherUid}`);
    const endedAt = firestore_1.Timestamp.now();
    const endedAtMs = endedAt.toMillis();
    const lessonRecord = await loadLessonDocByQuestionId(questionId);
    const pricing = await resolveLessonPricing(studentUid, lessonRecord === null || lessonRecord === void 0 ? void 0 : lessonRecord.data);
    const { currencyCode, pricePerMinute, teacherShare, exchangeRateToUsd } = pricing;
    // Bill from the moment both parties were fully connected (startedAt).
    // If startLesson was never called the lesson never properly began — charge 0.
    const billingStartMs = startedAtMs !== null && startedAtMs !== void 0 ? startedAtMs : endedAtMs;
    const { rawSeconds, roundedSeconds, roundedMinutes, minutesToCharge: roundedMinutesToCharge, cost, teacherEarnings, } = (0, billing_1.calculateBilling)(billingStartMs, endedAtMs, pricePerMinute, teacherShare);
    const migratedQuestion = sanitizeForFirestore(rtdbQuestion);
    firebase_functions_1.logger.info(`[lessons] migrateQuestionToFirestore payload qid=${questionId} rtdbKeys=${Object.keys(rtdbQuestion).sort().join(",") || "none"}`);
    firebase_functions_1.logger.info(`[lessons] cost computed qid=${questionId} rawSeconds=${rawSeconds} roundedSeconds=${roundedSeconds} currency=${currencyCode} pricePerMinute=${pricePerMinute} cost=${cost} teacherShare=${teacherShare} teacherEarnings=${teacherEarnings}`);
    const batch = firestore.batch();
    const qDocRef = firestore.collection("questions").doc(questionId);
    batch.set(qDocRef, Object.assign(Object.assign({}, migratedQuestion), { state: "ended", status: "completed", studentUid, acceptedByTeacher: teacherUid, teacherId: teacherUid, participants: [studentUid, teacherUid], durationSeconds: roundedSeconds, currencyCode,
        pricePerMinute,
        exchangeRateToUsd,
        teacherShare,
        cost,
        teacherEarnings, 
        // Legacy aliases for clients still reading the old field names.
        costPerMinute: pricePerMinute, commissionRate: teacherShare, endedBy,
        endedAt, updatedAt: firestore_1.FieldValue.serverTimestamp() }), { merge: true });
    if (lessonRecord) {
        batch.set(lessonRecord.ref, {
            currencyCode,
            pricePerMinute,
            teacherShare,
            exchangeRateToUsd,
            cost,
            teacherEarnings,
            billedSeconds: roundedSeconds,
            durationSeconds: roundedSeconds,
            endedBy,
            endedAt,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
    }
    const studentRef = firestore.collection("users").doc(studentUid);
    const teacherRef = firestore.collection("users").doc(teacherUid);
    batch.set(studentRef, {
        questions: firestore_1.FieldValue.arrayUnion(questionId),
        remainingMinutes: firestore_1.FieldValue.increment(-roundedMinutesToCharge),
        totalMinutesUsed: firestore_1.FieldValue.increment(roundedMinutesToCharge),
    }, { merge: true });
    batch.set(teacherRef, {
        questions: firestore_1.FieldValue.arrayUnion(questionId),
        totalMinutes: firestore_1.FieldValue.increment(roundedMinutes),
        totalEarnings: firestore_1.FieldValue.increment(teacherEarnings),
        earnings: firestore_1.FieldValue.increment(teacherEarnings),
        totalRevenueGenerated: firestore_1.FieldValue.increment(cost),
    }, { merge: true });
    if (roundedMinutesToCharge > 0) {
        const purchasesSnap = await firestore
            .collection("users")
            .doc(studentUid)
            .collection("purchases")
            .where("status", "==", "active")
            .limit(50)
            .get();
        const sortedPurchases = [...purchasesSnap.docs].sort((a, b) => {
            var _a, _b, _c, _d, _e, _f;
            const aTs = (_c = (_b = (_a = a.data().purchasedAt) === null || _a === void 0 ? void 0 : _a.toMillis) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : 0;
            const bTs = (_f = (_e = (_d = b.data().purchasedAt) === null || _d === void 0 ? void 0 : _d.toMillis) === null || _e === void 0 ? void 0 : _e.call(_d)) !== null && _f !== void 0 ? _f : 0;
            return aTs - bTs;
        });
        let minutesToConsume = roundedMinutesToCharge;
        for (const purchaseDoc of sortedPurchases) {
            if (minutesToConsume <= 0)
                break;
            const purchase = purchaseDoc.data();
            const purchaseRef = purchaseDoc.ref;
            const currentRemaining = Math.max(0, Number((_a = purchase.minutesRemaining) !== null && _a !== void 0 ? _a : 0));
            if (currentRemaining <= 0) {
                batch.set(purchaseRef, {
                    status: "expired",
                    updatedAt: firestore_1.Timestamp.now(),
                }, { merge: true });
                continue;
            }
            const usedNow = Math.min(currentRemaining, minutesToConsume);
            const nextRemaining = Math.max(0, Math.round((currentRemaining - usedNow) * 100) / 100);
            minutesToConsume = Math.max(0, Math.round((minutesToConsume - usedNow) * 100) / 100);
            batch.set(purchaseRef, {
                minutesRemaining: nextRemaining,
                minutesUsed: firestore_1.FieldValue.increment(usedNow),
                status: nextRemaining === 0 ? "expired" : "active",
                updatedAt: firestore_1.Timestamp.now(),
            }, { merge: true });
        }
        const consumedFromPurchases = roundedMinutesToCharge - minutesToConsume;
        batch.set(studentRef, {
            purchaseMinutesConsumed: firestore_1.FieldValue.increment(consumedFromPurchases),
        }, { merge: true });
        firebase_functions_1.logger.info(`[lessons] purchase consumption qid=${questionId} studentUid=${studentUid} roundedMinutes=${roundedMinutesToCharge} consumedFromPurchases=${consumedFromPurchases} remainingUnmapped=${minutesToConsume}`);
    }
    await batch.commit();
    firebase_functions_1.logger.info(`[lessons] migrateQuestionToFirestore firestore batch committed qid=${questionId}`);
    const existsBeforeRemove = (await questionRef.once("value")).exists();
    firebase_functions_1.logger.info(`[lessons] migrateQuestionToFirestore removing RTDB question qid=${questionId} existsBeforeRemove=${existsBeforeRemove}`);
    await questionRef.remove();
    firebase_functions_1.logger.info(`[lessons] migrateQuestionToFirestore RTDB question removed qid=${questionId}`);
}
// ─── startLesson ──────────────────────────────────────────────────────────────
// FR-B-006, FR-B-010
// Called by either client once the Agora audio channel is connected.
// Creates the /lessons doc and schedules the 30-minute hard-cap task.
exports.startLesson = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d;
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
    firebase_functions_1.logger.info(`[lessons] startLesson authorized qid=${questionId} uid=${uid} questionStatus=${q.status} acceptedByTeacher=${(_b = q.acceptedByTeacher) !== null && _b !== void 0 ? _b : "none"}`);
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
    const liveKitRoom = (_c = agoraTokenSnap.agoraChannel) !== null && _c !== void 0 ? _c : `lesson_${questionId}`;
    // Lock pricing at the moment the lesson starts so RC changes mid-lesson
    // do not retroactively shift the price. Currency is resolved from the
    // student's profile (/users/{uid}.currency).
    const pricing = await (0, pricing_1.resolvePricingForStudent)(q.studentUid);
    const pricePerMinuteCents = Math.round(pricing.pricePerMinute * 100);
    const lesson = {
        questionId,
        studentUid: q.studentUid,
        teacherUid: q.acceptedByTeacher,
        startedAt: firestore_1.Timestamp.fromDate(now),
        hardCapAt: firestore_1.Timestamp.fromDate(hardCapAt),
        baseRatePerMinCents: pricePerMinuteCents,
        connectionFeeCents: types_1.CONNECTION_FEE_CENTS,
        currencyCode: pricing.currency,
        pricePerMinute: pricing.pricePerMinute,
        teacherShare: pricing.teacherShare,
        exchangeRateToUsd: pricing.exchangeRateToUsd,
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
        currencyCode: pricing.currency,
        pricePerMinute: pricing.pricePerMinute,
        teacherShare: pricing.teacherShare,
        exchangeRateToUsd: pricing.exchangeRateToUsd,
        updatedAt: firestore_1.FieldValue.serverTimestamp(),
    });
    await batch.commit();
    firebase_functions_1.logger.info(`[lessons] startLesson firestore batch committed lessonId=${lessonId} qid=${questionId} currency=${pricing.currency} pricePerMinute=${pricing.pricePerMinute} teacherShare=${pricing.teacherShare}`);
    // Keep RTDB question state aligned for real-time clients.
    // Mirror the pricing snapshot so the in-progress UI can render live
    // earnings / cost without re-querying Firestore mid-call.
    const teacherSharePercent = Math.round(pricing.teacherShare * 100);
    firebase_functions_1.logger.info(`[lessons] startLesson syncing RTDB question qid=${questionId} status=in_progress teacherId=${(_d = q.acceptedByTeacher) !== null && _d !== void 0 ? _d : "none"}`);
    await db.ref(`questions/${questionId}`).update({
        status: "in_progress",
        questionId,
        studentUid: q.studentUid,
        teacherUid: q.acceptedByTeacher,
        acceptedByTeacher: q.acceptedByTeacher,
        teacherId: q.acceptedByTeacher,
        startedAt: Date.now(),
        updatedAt: Date.now(),
        currencyCode: pricing.currency,
        pricePerMinute: pricing.pricePerMinute,
        pricePerMinuteCents,
        teacherShare: pricing.teacherShare,
        teacherSharePercent,
        exchangeRateToUsd: pricing.exchangeRateToUsd,
        connectionFeeCents: types_1.CONNECTION_FEE_CENTS,
    });
    firebase_functions_1.logger.info(`[lessons] startLesson RTDB sync complete qid=${questionId}`);
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
    var _a, _b, _c, _d;
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
        const questionDoc = await firestore.collection("questions").doc(questionId).get();
        const lessonId = (_b = questionDoc.data()) === null || _b === void 0 ? void 0 : _b.lessonId;
        if (lessonId) {
            await firestore.collection("lessons").doc(lessonId).set({
                status: "completed",
                endedBy,
                endedAt: firestore_1.FieldValue.serverTimestamp(),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            }, { merge: true });
            firebase_functions_1.logger.info(`[lessons] endLesson lesson completed lessonId=${lessonId} qid=${questionId}`);
        }
        debugContext.stage = "completed";
        firebase_functions_1.logger.info(`[lessons] endLesson migrated qid=${questionId} from RTDB to Firestore and marked ended`);
        firebase_functions_1.logger.info(`[lessons] endLesson triggering dispatch backfill for teacher=${context.teacherUid} qid=${questionId} endedBy=${endedBy}`);
        try {
            await (0, dispatch_1.backfillPendingQuestionsForTeacher)(context.teacherUid);
        }
        catch (backfillError) {
            const backfillMessage = backfillError instanceof Error
                ? backfillError.message
                : String(backfillError);
            firebase_functions_1.logger.error(`[lessons] endLesson backfill failed qid=${questionId} teacher=${context.teacherUid} message=${backfillMessage}`);
        }
        return { success: true, questionId, endedBy };
    }
    catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        const stack = error instanceof Error ? error.stack : undefined;
        firebase_functions_1.logger.error(`[lessons] endLesson failed stage=${String(debugContext.stage)} qid=${String((_c = debugContext.questionId) !== null && _c !== void 0 ? _c : "unknown")} uid=${String((_d = debugContext.uid) !== null && _d !== void 0 ? _d : "unknown")} message=${message}`);
        firebase_functions_1.logger.error(`[lessons] endLesson debugContext=${JSON.stringify(debugContext)}`);
        if (stack) {
            firebase_functions_1.logger.error(`[lessons] endLesson stack=${stack}`);
        }
        if (error instanceof https_1.HttpsError)
            throw error;
        throw new https_1.HttpsError("internal", `endLesson failed: ${message}`);
    }
});
// ─── rateTeacher ────────────────────────────────────────────────────────────
// FR-B-010: callable — student rates the teacher for a finished lesson.
exports.rateTeacher = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const data = req.data;
    const questionId = data.questionId;
    const teacherId = data.teacherId;
    const rating = Number(data.rating);
    if (!questionId)
        throw new https_1.HttpsError("invalid-argument", "questionId required");
    if (!teacherId)
        throw new https_1.HttpsError("invalid-argument", "teacherId required");
    if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
        throw new https_1.HttpsError("invalid-argument", "rating must be an integer from 1 to 5");
    }
    const questionRef = firestore.collection("questions").doc(questionId);
    const teacherRef = firestore.collection("teachers").doc(teacherId);
    const ratingRef = teacherRef.collection("ratings").doc(questionId);
    await firestore.runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e;
        const [questionSnap, teacherSnap, existingRatingSnap] = await Promise.all([
            tx.get(questionRef),
            tx.get(teacherRef),
            tx.get(ratingRef),
        ]);
        if (!questionSnap.exists) {
            throw new https_1.HttpsError("not-found", "Question not found");
        }
        const question = questionSnap.data();
        if (question.studentUid !== uid) {
            throw new https_1.HttpsError("permission-denied", "Only the student in this lesson can rate it");
        }
        const ratedTeacherId = question.teacherUid;
        if (question.acceptedByTeacher !== teacherId && ratedTeacherId !== teacherId) {
            throw new https_1.HttpsError("failed-precondition", "teacherId does not match this question");
        }
        const q = question;
        let lessonForRating;
        if (typeof q.lessonId === "string" && q.lessonId.trim().length > 0) {
            const lessonSnap = await tx.get(firestore.collection("lessons").doc(q.lessonId));
            if (lessonSnap.exists) {
                lessonForRating = lessonSnap.data();
            }
        }
        const lessonFinished = Boolean(lessonForRating && (lessonForRating.status === "completed" ||
            toTimestamp(lessonForRating.endedAt)));
        const questionFinished = q.status === "completed" || q.state === "ended";
        if (!questionFinished && !lessonFinished) {
            throw new https_1.HttpsError("failed-precondition", "Lesson must be completed before rating");
        }
        if (existingRatingSnap.exists) {
            return;
        }
        const teacherData = ((_a = teacherSnap.data()) !== null && _a !== void 0 ? _a : {});
        const ratingsSnap = await tx.get(teacherRef.collection("ratings"));
        const ratingCount = ratingsSnap.size;
        const currentAverage = Number.isFinite(Number(teacherData.averageRate))
            ? Number(teacherData.averageRate)
            : 0;
        const nextAverage = ratingCount === 0
            ? rating
            : ((ratingCount * currentAverage) + rating) / (ratingCount + 1);
        let startedAt = (_c = (_b = toTimestamp(q.startedAt)) !== null && _b !== void 0 ? _b : toTimestamp(q.acceptedAt)) !== null && _c !== void 0 ? _c : toTimestamp(q.createdAt);
        let endedAt = toTimestamp(q.endedAt);
        if (lessonForRating) {
            startedAt = (_d = toTimestamp(lessonForRating.startedAt)) !== null && _d !== void 0 ? _d : startedAt;
            endedAt = (_e = toTimestamp(lessonForRating.endedAt)) !== null && _e !== void 0 ? _e : endedAt;
        }
        const safeEndedAt = endedAt !== null && endedAt !== void 0 ? endedAt : firestore_1.Timestamp.now();
        const safeStartedAt = startedAt !== null && startedAt !== void 0 ? startedAt : safeEndedAt;
        const ratingDoc = {
            startedAt: safeStartedAt,
            endedAt: safeEndedAt,
            studentId: uid,
            studentRate: rating,
        };
        tx.set(ratingRef, ratingDoc);
        tx.set(teacherRef, { averageRate: nextAverage }, { merge: true });
    });
    return { success: true };
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