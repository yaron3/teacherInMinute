"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.evaluateWave = exports.dispatchQuestion = void 0;
exports.backfillPendingQuestionsForTeacher = backfillPendingQuestionsForTeacher;
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
async function archiveUnanswered(qid, alreadyInvited) {
    firebase_functions_1.logger.warn(`[dispatch] archiveUnanswered start qid=${qid} invitedCount=${alreadyInvited.length}`);
    const questionRef = db.ref(`questions/${qid}`);
    const questionExists = (await questionRef.once("value")).exists();
    firebase_functions_1.logger.warn(`[dispatch] archiveUnanswered precheck qid=${qid} rtdbQuestionExists=${questionExists}`);
    const qRef = firestore.collection("questions").doc(qid);
    const archived = await firestore.runTransaction(async (tx) => {
        const snap = await tx.get(qRef);
        if (!snap.exists) {
            firebase_functions_1.logger.warn(`[dispatch] archiveUnanswered skipped qid=${qid} reason=question-not-found`);
            return false;
        }
        const current = snap.data();
        if (current.status !== "searching") {
            firebase_functions_1.logger.info(`[dispatch] archiveUnanswered skipped qid=${qid} reason=status-changed status=${current.status}`);
            return false;
        }
        tx.update(qRef, {
            status: "unanswered",
            endedAt: firestore_2.FieldValue.serverTimestamp(),
            updatedAt: firestore_2.FieldValue.serverTimestamp(),
        });
        return true;
    });
    if (!archived) {
        firebase_functions_1.logger.info(`[dispatch] archiveUnanswered done qid=${qid} archived=false cleanupSkipped=true`);
        return false;
    }
    firebase_functions_1.logger.warn(`[dispatch] archiveUnanswered firestore-status-updated qid=${qid} status=unanswered`);
    await Promise.all([
        questionRef.remove(),
        ...alreadyInvited.map((tid) => db.ref(`teacherInvites/${tid}/${qid}`).remove()),
    ]);
    firebase_functions_1.logger.warn(`[dispatch] archiveUnanswered done qid=${qid} removedQuestion=${questionExists} removedTeacherInvites=${alreadyInvited.length}`);
    return true;
}
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
    firebase_functions_1.logger.info(`[dispatch] sendWave prepared qid=${qid} wave=${wave} teacherPool=${Object.keys(teachers).length} excluded=${exclude.size} eligible=${ranked.length} selected=${batch.length}`);
    if (batch.length === 0)
        return [];
    const now = firestore_2.Timestamp.now();
    const expiresAt = firestore_2.Timestamp.fromMillis(Date.now() + types_1.INVITE_EXPIRY_SECONDS * 1000);
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
            conversationType: questionData.conversationType,
        };
        firestoreBatch.set(inviteRef, invite);
    }
    await firestoreBatch.commit();
    firebase_functions_1.logger.info(`[dispatch] sendWave firestore invites committed qid=${qid} wave=${wave} count=${batch.length}`);
    // RTDB signals — the app listens to teacherInvites/{uid}/{qid} for real-time invite delivery.
    // Written in parallel with FCM so the app catches invites even without a push token.
    const teacherRecords = await allTeachers();
    await Promise.all(batch.map(async ({ uid }) => {
        await db.ref(`teacherInvites/${uid}/${qid}`).set({
            topic: questionData.topic,
            text: questionData.text.slice(0, 300),
            expiresAt: Date.now() + types_1.INVITE_EXPIRY_SECONDS * 1000,
            wave,
            conversationType: questionData.conversationType,
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
                ttlSeconds: types_1.INVITE_EXPIRY_SECONDS,
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
async function tryInviteTeacherForQuestionWave(teacherUid, teacher, qid) {
    const qRef = firestore.collection("questions").doc(qid);
    const inviteRef = qRef.collection("invites").doc(teacherUid);
    const result = await firestore.runTransaction(async (tx) => {
        var _a, _b;
        const qSnap = await tx.get(qRef);
        if (!qSnap.exists)
            return { invited: false, reason: "question-not-found" };
        const question = qSnap.data();
        if (question.status !== "searching")
            return { invited: false, reason: `status-${question.status}` };
        const wave = question.dispatchWave;
        if (!wave || wave < 1 || wave > types_1.WAVE_SIZES.length) {
            return { invited: false, reason: `invalid-wave-${wave !== null && wave !== void 0 ? wave : 0}` };
        }
        if (!((_a = teacher.subjects) === null || _a === void 0 ? void 0 : _a.includes(question.topic))) {
            return { invited: false, reason: "topic-mismatch" };
        }
        const alreadyInvited = new Set((_b = question.alreadyInvited) !== null && _b !== void 0 ? _b : []);
        if (alreadyInvited.has(teacherUid)) {
            return { invited: false, reason: "already-invited" };
        }
        const ranked = (0, scoring_1.rankTeachers)({ [teacherUid]: teacher }, question.topic, alreadyInvited);
        if (ranked.length === 0) {
            return { invited: false, reason: "not-eligible-now" };
        }
        const waveSize = types_1.WAVE_SIZES[wave - 1];
        const waveInviteQuery = qRef.collection("invites").where("wave", "==", wave);
        const waveInvitesSnap = await tx.get(waveInviteQuery);
        if (waveInvitesSnap.size >= waveSize) {
            return { invited: false, reason: `wave-full-${waveInvitesSnap.size}/${waveSize}` };
        }
        const now = firestore_2.Timestamp.now();
        const expiresAt = firestore_2.Timestamp.fromMillis(Date.now() + types_1.INVITE_EXPIRY_SECONDS * 1000);
        const invite = {
            teacherUid,
            questionId: qid,
            sentAt: now,
            expiresAt,
            response: "pending",
            wave,
            conversationType: question.conversationType,
        };
        tx.set(inviteRef, invite);
        tx.update(qRef, {
            alreadyInvited: firestore_2.FieldValue.arrayUnion(teacherUid),
            updatedAt: firestore_2.FieldValue.serverTimestamp(),
        });
        return {
            invited: true,
            reason: `wave-backfill-${wave}`,
            topic: question.topic,
            text: question.text,
            studentUid: question.studentUid,
            wave,
            conversationType: question.conversationType,
        };
    });
    if (!result.invited) {
        firebase_functions_1.logger.info(`[dispatch] teacher backfill skipped qid=${qid} teacher=${teacherUid} reason=${result.reason}`);
        return false;
    }
    const invitePayload = result;
    await db.ref(`teacherInvites/${teacherUid}/${qid}`).set({
        topic: invitePayload.topic,
        text: invitePayload.text.slice(0, 300),
        expiresAt: Date.now() + types_1.INVITE_EXPIRY_SECONDS * 1000,
        wave: invitePayload.wave,
        conversationType: invitePayload.conversationType,
    });
    if (teacher.fcmToken) {
        await (0, fcm_1.sendInvitePush)({
            fcmToken: teacher.fcmToken,
            questionId: qid,
            topic: invitePayload.topic,
            studentName: invitePayload.studentUid,
            questionText: invitePayload.text,
            wave: invitePayload.wave,
            ttlSeconds: types_1.INVITE_EXPIRY_SECONDS,
        });
    }
    firebase_functions_1.logger.info(`[dispatch] teacher backfill invited qid=${qid} teacher=${teacherUid} wave=${invitePayload.wave}`);
    return true;
}
async function backfillPendingQuestionsForTeacher(teacherUid) {
    const teacherSnap = await db.ref(`teachers/${teacherUid}`).once("value");
    const teacher = teacherSnap.val();
    if (!teacher || teacher.status !== "online") {
        firebase_functions_1.logger.info(`[dispatch] backfill skipped teacher=${teacherUid} reason=teacher-offline-or-missing`);
        return;
    }
    const searchingSnap = await firestore
        .collection("questions")
        .where("status", "==", "searching")
        .limit(50)
        .get();
    if (searchingSnap.empty) {
        firebase_functions_1.logger.info(`[dispatch] backfill teacher=${teacherUid} no-searching-questions`);
        return;
    }
    const orderedSearchingDocs = [...searchingSnap.docs].sort((a, b) => {
        var _a, _b, _c, _d, _e, _f;
        const aCreated = (_c = (_b = (_a = a.data().createdAt) === null || _a === void 0 ? void 0 : _a.toMillis) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : 0;
        const bCreated = (_f = (_e = (_d = b.data().createdAt) === null || _d === void 0 ? void 0 : _d.toMillis) === null || _e === void 0 ? void 0 : _e.call(_d)) !== null && _f !== void 0 ? _f : 0;
        return aCreated - bCreated;
    });
    let invitedCount = 0;
    for (const doc of orderedSearchingDocs) {
        const invited = await tryInviteTeacherForQuestionWave(teacherUid, teacher, doc.id);
        if (invited) {
            invitedCount += 1;
            break;
        }
    }
    firebase_functions_1.logger.info(`[dispatch] backfill completed teacher=${teacherUid} invitedCount=${invitedCount} searched=${searchingSnap.size}`);
}
// ─── dispatchQuestion — Firestore onCreate trigger ───────────────────────────
// FR-B-001, FR-B-002, FR-B-003
exports.dispatchQuestion = (0, firestore_1.onDocumentCreated)("questions/{qid}", async (event) => {
    var _a, _b;
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
    firebase_functions_1.logger.info(`[dispatch] initial status qid=${qid} status=${data.status} alreadyInvited=${((_b = data.alreadyInvited) !== null && _b !== void 0 ? _b : []).length}`);
    const invited = await sendWave(qid, data, 1, new Set());
    if (invited.length === 0) {
        // No eligible teachers at all — declare unanswered immediately
        const archived = await archiveUnanswered(qid, []);
        if (archived) {
            firebase_functions_1.logger.info(`[dispatch] no teachers found for qid=${qid}, declared unanswered`);
        }
        else {
            firebase_functions_1.logger.info(`[dispatch] no teachers found for qid=${qid}, unanswered skipped`);
        }
        return;
    }
    await firestore.collection("questions").doc(qid).update({
        dispatchWave: 1,
        alreadyInvited: firestore_2.FieldValue.arrayUnion(...invited),
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    });
    firebase_functions_1.logger.info(`[dispatch] qid=${qid} dispatchWave updated to 1 invitedNow=${invited.length}`);
    await enqueueWaveEvaluation(qid, 1);
});
// ─── evaluateWave — Cloud Tasks handler ──────────────────────────────────────
// FR-B-003, FR-B-005
// Called WAVE_TIMEOUT_SECONDS after each wave. Fans out the next wave without
// cancelling earlier invites — all teachers have INVITE_EXPIRY_SECONDS to accept.
exports.evaluateWave = (0, tasks_1.onTaskDispatched)({
    retryConfig: { maxAttempts: 1 },
    rateLimits: { maxConcurrentDispatches: 50 },
}, async (req) => {
    var _a, _b, _c, _d, _e;
    const { questionId: qid, wave } = req.data;
    firebase_functions_1.logger.info(`[evaluateWave] start qid=${qid} wave=${wave}`);
    const qRef = firestore.collection("questions").doc(qid);
    const qSnap = await qRef.get();
    if (!qSnap.exists) {
        firebase_functions_1.logger.warn(`[evaluateWave] qid=${qid} not found`);
        return;
    }
    const data = qSnap.data();
    firebase_functions_1.logger.info(`[evaluateWave] state qid=${qid} status=${data.status} dispatchWave=${(_a = data.dispatchWave) !== null && _a !== void 0 ? _a : 0} alreadyInvited=${((_b = data.alreadyInvited) !== null && _b !== void 0 ? _b : []).length}`);
    if (data.status !== "searching") {
        firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} already ${data.status}, skipping wave=${wave}`);
        return;
    }
    // Invites from this wave remain pending — teachers have INVITE_EXPIRY_SECONDS total to accept.
    // Only fan out the next wave so more teachers are notified sooner.
    const nextWave = wave + 1;
    // FR-B-005: after wave 3 with no acceptance, declare unanswered
    if (nextWave > types_1.WAVE_SIZES.length) {
        firebase_functions_1.logger.warn(`[evaluateWave] max waves reached qid=${qid} currentWave=${wave} nextWave=${nextWave}`);
        const archived = await archiveUnanswered(qid, (_c = data.alreadyInvited) !== null && _c !== void 0 ? _c : []);
        if (archived) {
            firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} declared unanswered after wave ${wave}`);
        }
        else {
            firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} unanswered skipped after wave ${wave}`);
        }
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
    const alreadyInvited = new Set((_d = data.alreadyInvited) !== null && _d !== void 0 ? _d : []);
    const invited = await sendWave(qid, data, nextWave, alreadyInvited);
    if (invited.length === 0) {
        // Ran out of eligible teachers mid-dispatch
        const archived = await archiveUnanswered(qid, (_e = data.alreadyInvited) !== null && _e !== void 0 ? _e : []);
        if (archived) {
            firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} no teachers for wave=${nextWave}, unanswered`);
        }
        else {
            firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} no teachers for wave=${nextWave}, unanswered skipped`);
        }
        return;
    }
    await qRef.update({
        dispatchWave: nextWave,
        alreadyInvited: firestore_2.FieldValue.arrayUnion(...invited),
        updatedAt: firestore_2.FieldValue.serverTimestamp(),
    });
    firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} dispatchWave updated to ${nextWave} invitedNow=${invited.length}`);
    await enqueueWaveEvaluation(qid, nextWave);
    firebase_functions_1.logger.info(`[evaluateWave] qid=${qid} wave=${nextWave} enqueued`);
});
//# sourceMappingURL=dispatch.js.map