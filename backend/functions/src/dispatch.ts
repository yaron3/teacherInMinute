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
} from "./types";

const db = admin.database();
const firestore = admin.firestore();

// ─── helpers ─────────────────────────────────────────────────────────────────

async function archiveUnanswered(qid: string, alreadyInvited: string[]): Promise<void> {
  await firestore.collection("questions").doc(qid).update({
    status: "unanswered",
    endedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  await Promise.all([
    db.ref(`questions/${qid}`).remove(),
    ...alreadyInvited.map((tid) => db.ref(`teacherInvites/${tid}/${qid}`).remove()),
  ]);
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
    };
    firestoreBatch.set(inviteRef, invite);
  }

  await firestoreBatch.commit();

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

    const invited = await sendWave(qid, data, 1, new Set<string>());

    if (invited.length === 0) {
      // No eligible teachers at all — declare unanswered immediately
      await archiveUnanswered(qid, []);
      logger.info(`[dispatch] no teachers found for qid=${qid}, declared unanswered`);
      return;
    }

    await firestore.collection("questions").doc(qid).update({
      dispatchWave: 1,
      alreadyInvited: FieldValue.arrayUnion(...invited),
      updatedAt: FieldValue.serverTimestamp(),
    });

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

    const qRef = firestore.collection("questions").doc(qid);
    const qSnap = await qRef.get();

    if (!qSnap.exists) {
      logger.warn(`[evaluateWave] qid=${qid} not found`);
      return;
    }

    const data = qSnap.data() as QuestionDoc;

    if (data.status !== "searching") {
      logger.info(`[evaluateWave] qid=${qid} already ${data.status}, skipping wave=${wave}`);
      return;
    }

    // Invites from this wave remain pending — teachers have INVITE_EXPIRY_SECONDS total to accept.
    // Only fan out the next wave so more teachers are notified sooner.
    const nextWave = wave + 1;

    // FR-B-005: after wave 3 with no acceptance, declare unanswered
    if (nextWave > WAVE_SIZES.length) {
      await archiveUnanswered(qid, data.alreadyInvited ?? []);
      logger.info(`[evaluateWave] qid=${qid} declared unanswered after wave ${wave}`);

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
      await archiveUnanswered(qid, data.alreadyInvited ?? []);
      logger.info(`[evaluateWave] qid=${qid} no teachers for wave=${nextWave}, unanswered`);
      return;
    }

    await qRef.update({
      dispatchWave: nextWave,
      alreadyInvited: FieldValue.arrayUnion(...invited),
      updatedAt: FieldValue.serverTimestamp(),
    });

    await enqueueWaveEvaluation(qid, nextWave);
    logger.info(`[evaluateWave] qid=${qid} wave=${nextWave} enqueued`);
  }
);
