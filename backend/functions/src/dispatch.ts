import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { getFunctions } from "firebase-admin/functions";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { rankTeachers } from "./scoring";
import { sendInvitePush, sendNoMatchPush } from "./fcm";
import {
  TeacherRecord,
  QuestionDoc,
  DispatchInviteDoc,
  WAVE_SIZES,
  WAVE_TIMEOUT_SECONDS,
  INVITE_EXPIRY_SECONDS,
  ConversationType,
} from "./types";

const db = admin.database();
const firestore = admin.firestore();

// ─── helpers ─────────────────────────────────────────────────────────────────

async function archiveUnanswered(qid: string, alreadyInvited: string[]): Promise<boolean> {
  logger.warn(
    `[dispatch] archiveUnanswered start qid=${qid} invitedCount=${alreadyInvited.length}`
  );

  const questionRef = db.ref(`questions/${qid}`);
  const questionExists = (await questionRef.once("value")).exists();
  logger.warn(
    `[dispatch] archiveUnanswered precheck qid=${qid} rtdbQuestionExists=${questionExists}`
  );

  const qRef = firestore.collection("questions").doc(qid);
  const archived = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(qRef);
    if (!snap.exists) {
      logger.warn(`[dispatch] archiveUnanswered skipped qid=${qid} reason=question-not-found`);
      return false;
    }

    const current = snap.data() as QuestionDoc;
    if (current.status !== "searching") {
      logger.info(
        `[dispatch] archiveUnanswered skipped qid=${qid} reason=status-changed status=${current.status}`
      );
      return false;
    }

    tx.update(qRef, {
      status: "unanswered",
      endedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return true;
  });

  if (!archived) {
    logger.info(`[dispatch] archiveUnanswered done qid=${qid} archived=false cleanupSkipped=true`);
    return false;
  }

  logger.warn(`[dispatch] archiveUnanswered firestore-status-updated qid=${qid} status=unanswered`);

  await Promise.all([
    questionRef.remove(),
    ...alreadyInvited.map((tid) => db.ref(`teacherInvites/${tid}/${qid}`).remove()),
  ]);

  logger.warn(
    `[dispatch] archiveUnanswered done qid=${qid} removedQuestion=${questionExists} removedTeacherInvites=${alreadyInvited.length}`
  );

  return true;
}

async function allTeachers(): Promise<Record<string, TeacherRecord>> {
  const snap = await db.ref("teachers").once("value");
  return (snap.val() as Record<string, TeacherRecord>) ?? {};
}

async function sendWave(
  qid: string,
  questionData: QuestionDoc,
  wave: number,
  exclude: Set<string>
): Promise<string[]> {
  const teachers = await allTeachers();
  const ranked = rankTeachers(teachers, questionData.topic, exclude);
  const waveSize = WAVE_SIZES[wave - 1];
  const batch = ranked.slice(0, waveSize);

  logger.info(
    `[dispatch] sendWave prepared qid=${qid} wave=${wave} teacherPool=${Object.keys(teachers).length} excluded=${exclude.size} eligible=${ranked.length} selected=${batch.length}`
  );

  if (batch.length === 0) return [];

  const now = Timestamp.now();
  const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_EXPIRY_SECONDS * 1000);
  const firestoreBatch = firestore.batch();

  for (const { uid } of batch) {
    const inviteRef = firestore
      .collection("questions")
      .doc(qid)
      .collection("invites")
      .doc(uid);

    const invite: DispatchInviteDoc = {
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
  logger.info(`[dispatch] sendWave firestore invites committed qid=${qid} wave=${wave} count=${batch.length}`);

  // RTDB signals — the app listens to teacherInvites/{uid}/{qid} for real-time invite delivery.
  // Written in parallel with FCM so the app catches invites even without a push token.
  const teacherRecords = await allTeachers();
  await Promise.all(
    batch.map(async ({ uid }) => {
      await db.ref(`teacherInvites/${uid}/${qid}`).set({
        topic: questionData.topic,
        text: questionData.text.slice(0, 300),
        expiresAt: Date.now() + INVITE_EXPIRY_SECONDS * 1000,
        wave,
        conversationType: questionData.conversationType,
      });

      // FCM on top of RTDB — best-effort, no-op if no token
      const t = teacherRecords[uid];
      if (t?.fcmToken) {
        await sendInvitePush({
          fcmToken: t.fcmToken,
          questionId: qid,
          topic: questionData.topic,
          studentName: questionData.studentUid,
          questionText: questionData.text,
          wave,
          ttlSeconds: INVITE_EXPIRY_SECONDS,
        });
      }
    })
  );

  logger.info(`[dispatch] wave=${wave} qid=${qid} sent to ${batch.length} teachers`);
  return batch.map((t) => t.uid);
}

async function enqueueWaveEvaluation(qid: string, wave: number): Promise<void> {
  const queue = getFunctions().taskQueue("evaluateWave");
  await queue.enqueue(
    { questionId: qid, wave },
    { scheduleDelaySeconds: WAVE_TIMEOUT_SECONDS }
  );
}

async function tryInviteTeacherForQuestionWave(
  teacherUid: string,
  teacher: TeacherRecord,
  qid: string
): Promise<boolean> {
  const qRef = firestore.collection("questions").doc(qid);
  const inviteRef = qRef.collection("invites").doc(teacherUid);

  const result = await firestore.runTransaction(async (tx) => {
    const qSnap = await tx.get(qRef);
    if (!qSnap.exists) return { invited: false, reason: "question-not-found" };

    const question = qSnap.data() as QuestionDoc;
    if (question.status !== "searching") return { invited: false, reason: `status-${question.status}` };

    const wave = question.dispatchWave;
    if (!wave || wave < 1 || wave > WAVE_SIZES.length) {
      return { invited: false, reason: `invalid-wave-${wave ?? 0}` };
    }

    if (!teacher.subjects?.includes(question.topic)) {
      return { invited: false, reason: "topic-mismatch" };
    }

    const alreadyInvited = new Set(question.alreadyInvited ?? []);
    if (alreadyInvited.has(teacherUid)) {
      return { invited: false, reason: "already-invited" };
    }

    const ranked = rankTeachers({ [teacherUid]: teacher }, question.topic, alreadyInvited);
    if (ranked.length === 0) {
      return { invited: false, reason: "not-eligible-now" };
    }

    const waveSize = WAVE_SIZES[wave - 1];
    const waveInviteQuery = qRef.collection("invites").where("wave", "==", wave);
    const waveInvitesSnap = await tx.get(waveInviteQuery);
    if (waveInvitesSnap.size >= waveSize) {
      return { invited: false, reason: `wave-full-${waveInvitesSnap.size}/${waveSize}` };
    }

    const now = Timestamp.now();
    const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_EXPIRY_SECONDS * 1000);
    const invite: DispatchInviteDoc = {
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
      alreadyInvited: FieldValue.arrayUnion(teacherUid),
      updatedAt: FieldValue.serverTimestamp(),
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
    logger.info(
      `[dispatch] teacher backfill skipped qid=${qid} teacher=${teacherUid} reason=${result.reason}`
    );
    return false;
  }

  const invitePayload = result as {
    invited: true;
    reason: string;
    topic: string;
    text: string;
    studentUid: string;
    wave: number;
    conversationType: ConversationType;
  };

  await db.ref(`teacherInvites/${teacherUid}/${qid}`).set({
    topic: invitePayload.topic,
    text: invitePayload.text.slice(0, 300),
    expiresAt: Date.now() + INVITE_EXPIRY_SECONDS * 1000,
    wave: invitePayload.wave,
    conversationType: invitePayload.conversationType,
  });

  if (teacher.fcmToken) {
    await sendInvitePush({
      fcmToken: teacher.fcmToken,
      questionId: qid,
      topic: invitePayload.topic,
      studentName: invitePayload.studentUid,
      questionText: invitePayload.text,
      wave: invitePayload.wave,
      ttlSeconds: INVITE_EXPIRY_SECONDS,
    });
  }

  logger.info(
    `[dispatch] teacher backfill invited qid=${qid} teacher=${teacherUid} wave=${invitePayload.wave}`
  );
  return true;
}

export async function backfillPendingQuestionsForTeacher(teacherUid: string): Promise<void> {
  const teacherSnap = await db.ref(`teachers/${teacherUid}`).once("value");
  const teacher = teacherSnap.val() as TeacherRecord | null;

  if (!teacher || teacher.status !== "online") {
    logger.info(
      `[dispatch] backfill skipped teacher=${teacherUid} reason=teacher-offline-or-missing`
    );
    return;
  }

  const searchingSnap = await firestore
    .collection("questions")
    .where("status", "==", "searching")
    .limit(50)
    .get();

  if (searchingSnap.empty) {
    logger.info(`[dispatch] backfill teacher=${teacherUid} no-searching-questions`);
    return;
  }

  const orderedSearchingDocs = [...searchingSnap.docs].sort((a, b) => {
    const aCreated = (a.data() as Partial<QuestionDoc>).createdAt?.toMillis?.() ?? 0;
    const bCreated = (b.data() as Partial<QuestionDoc>).createdAt?.toMillis?.() ?? 0;
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

  logger.info(
    `[dispatch] backfill completed teacher=${teacherUid} invitedCount=${invitedCount} searched=${searchingSnap.size}`
  );
}

// ─── dispatchQuestion — Firestore onCreate trigger ───────────────────────────
// FR-B-001, FR-B-002, FR-B-003

export const dispatchQuestion = onDocumentCreated(
  "questions/{qid}",
  async (event) => {
    const qid = event.params.qid;
    const data = event.data?.data() as QuestionDoc | undefined;

    if (!data) {
      logger.error(`[dispatch] no data for qid=${qid}`);
      return;
    }

    if (data.status !== "searching") {
      logger.info(`[dispatch] skipping qid=${qid} status=${data.status}`);
      return;
    }

    logger.info(`[dispatch] starting dispatch for qid=${qid} topic=${data.topic}`);
    logger.info(
      `[dispatch] initial status qid=${qid} status=${data.status} alreadyInvited=${(data.alreadyInvited ?? []).length}`
    );

    const invited = await sendWave(qid, data, 1, new Set<string>());

    if (invited.length === 0) {
      // No eligible teachers at all — declare unanswered immediately
      const archived = await archiveUnanswered(qid, []);
      if (archived) {
        logger.info(`[dispatch] no teachers found for qid=${qid}, declared unanswered`);
      } else {
        logger.info(`[dispatch] no teachers found for qid=${qid}, unanswered skipped`);
      }
      return;
    }

    await firestore.collection("questions").doc(qid).update({
      dispatchWave: 1,
      alreadyInvited: FieldValue.arrayUnion(...invited),
      updatedAt: FieldValue.serverTimestamp(),
    });

    logger.info(`[dispatch] qid=${qid} dispatchWave updated to 1 invitedNow=${invited.length}`);

    await enqueueWaveEvaluation(qid, 1);
  }
);

// ─── evaluateWave — Cloud Tasks handler ──────────────────────────────────────
// FR-B-003, FR-B-005
// Called WAVE_TIMEOUT_SECONDS after each wave. Fans out the next wave without
// cancelling earlier invites — all teachers have INVITE_EXPIRY_SECONDS to accept.

export const evaluateWave = onTaskDispatched<{ questionId: string; wave: number }>(
  {
    retryConfig: { maxAttempts: 1 },
    rateLimits: { maxConcurrentDispatches: 50 },
  },
  async (req) => {
    const { questionId: qid, wave } = req.data;

    logger.info(`[evaluateWave] start qid=${qid} wave=${wave}`);

    const qRef = firestore.collection("questions").doc(qid);
    const qSnap = await qRef.get();

    if (!qSnap.exists) {
      logger.warn(`[evaluateWave] qid=${qid} not found`);
      return;
    }

    const data = qSnap.data() as QuestionDoc;

    logger.info(
      `[evaluateWave] state qid=${qid} status=${data.status} dispatchWave=${data.dispatchWave ?? 0} alreadyInvited=${(data.alreadyInvited ?? []).length}`
    );

    if (data.status !== "searching") {
      logger.info(`[evaluateWave] qid=${qid} already ${data.status}, skipping wave=${wave}`);
      return;
    }

    // Invites from this wave remain pending — teachers have INVITE_EXPIRY_SECONDS total to accept.
    // Only fan out the next wave so more teachers are notified sooner.
    const nextWave = wave + 1;

    // FR-B-005: after wave 3 with no acceptance, declare unanswered
    if (nextWave > WAVE_SIZES.length) {
      logger.warn(
        `[evaluateWave] max waves reached qid=${qid} currentWave=${wave} nextWave=${nextWave}`
      );
      const archived = await archiveUnanswered(qid, data.alreadyInvited ?? []);
      if (archived) {
        logger.info(`[evaluateWave] qid=${qid} declared unanswered after wave ${wave}`);
      } else {
        logger.info(`[evaluateWave] qid=${qid} unanswered skipped after wave ${wave}`);
      }

      // Notify student
      const studentFcmToken = await db
        .ref(`users/${data.studentUid}/fcmToken`)
        .once("value")
        .then((s) => s.val() as string | null);
      if (studentFcmToken) {
        await sendNoMatchPush({ fcmToken: studentFcmToken, questionId: qid });
      }
      return;
    }

    // Fan out next wave
    const alreadyInvited = new Set<string>(data.alreadyInvited ?? []);
    const invited = await sendWave(qid, data, nextWave, alreadyInvited);

    if (invited.length === 0) {
      // Ran out of eligible teachers mid-dispatch
      const archived = await archiveUnanswered(qid, data.alreadyInvited ?? []);
      if (archived) {
        logger.info(`[evaluateWave] qid=${qid} no teachers for wave=${nextWave}, unanswered`);
      } else {
        logger.info(`[evaluateWave] qid=${qid} no teachers for wave=${nextWave}, unanswered skipped`);
      }
      return;
    }

    await qRef.update({
      dispatchWave: nextWave,
      alreadyInvited: FieldValue.arrayUnion(...invited),
      updatedAt: FieldValue.serverTimestamp(),
    });

    logger.info(`[evaluateWave] qid=${qid} dispatchWave updated to ${nextWave} invitedNow=${invited.length}`);

    await enqueueWaveEvaluation(qid, nextWave);
    logger.info(`[evaluateWave] qid=${qid} wave=${nextWave} enqueued`);
  }
);
