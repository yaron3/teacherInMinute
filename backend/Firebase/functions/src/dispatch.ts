import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { onValueWritten } from "firebase-functions/v2/database";
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
  HOT_PATH,
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

/** Only the teachers who could actually take a question right now.
 *
 *  Filtered by RTDB rather than here: the node holds every teacher who has ever
 *  signed up, and pulling all of them down to discard the offline ones cost
 *  ~700ms on the dispatch path. Needs `.indexOn: ["status"]` on `teachers` in
 *  database.rules.json — without it RTDB still answers, but scans the node
 *  server-side and logs a warning. */
async function onlineTeachers(): Promise<Record<string, TeacherRecord>> {
  const snap = await db
    .ref("teachers")
    .orderByChild("status")
    .equalTo("online")
    .once("value");
  return (snap.val() as Record<string, TeacherRecord>) ?? {};
}

async function sendWave(
  qid: string,
  questionData: QuestionDoc,
  wave: number,
  exclude: Set<string>
): Promise<string[]> {
  const teachers = await onlineTeachers();
  const ranked = rankTeachers(teachers, questionData.topic, exclude);
  const waveSize = WAVE_SIZES[wave - 1];
  const batch = ranked.slice(0, waveSize);

  logger.info(
    `[dispatch] sendWave prepared qid=${qid} wave=${wave} onlinePool=${Object.keys(teachers).length} excluded=${exclude.size} eligible=${ranked.length} selected=${batch.length}`
  );

  if (batch.length === 0) return [];

  const now = Timestamp.now();
  const expiresAtMillis = Date.now() + INVITE_EXPIRY_SECONDS * 1000;
  const expiresAt = Timestamp.fromMillis(expiresAtMillis);

  // The teacher's dashboard watches teacherInvites/{uid}/{qid}, so that write —
  // not the Firestore invite doc, and not the push — is the instant the
  // question lands on their screen. It goes out first, and everything else runs
  // alongside it instead of in front of it.
  const invitePayload = {
    topic: questionData.topic,
    text: questionData.text.slice(0, 300),
    photoUrls: questionData.photoUrls ?? [],
    studentName: questionData.studentName ?? "",
    studentImageURL: questionData.studentImageURL ?? "",
    expiresAt: expiresAtMillis,
    wave,
    conversationType: questionData.conversationType,
  };

  const rtdbDelivery = Promise.all(
    batch.map(({ uid }) => db.ref(`teacherInvites/${uid}/${qid}`).set(invitePayload))
  );

  // acceptInvite reads this doc, so it has to exist before a teacher can claim
  // the question — but it is committed in parallel with the RTDB write above
  // rather than ahead of it. It lands a few hundred milliseconds later, which
  // is still far ahead of anyone reading the card and tapping Accept.
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
  const firestoreCommit = firestoreBatch.commit();

  // FCM only matters for a teacher whose app is backgrounded; a teacher looking
  // at the dashboard already has the invite from RTDB.
  const pushes = Promise.all(
    batch.map(async ({ uid }) => {
      const t = teachers[uid];
      if (!t?.fcmToken) return;
      await sendInvitePush({
        fcmToken: t.fcmToken,
        questionId: qid,
        topic: questionData.topic,
        studentName: questionData.studentName || questionData.studentUid,
        questionText: questionData.text,
        wave,
        ttlSeconds: INVITE_EXPIRY_SECONDS,
      });
    })
  );

  await rtdbDelivery;
  logger.info(`[dispatch] wave=${wave} qid=${qid} delivered to ${batch.length} teachers`);

  await Promise.all([firestoreCommit, pushes]);
  logger.info(`[dispatch] wave=${wave} qid=${qid} invites+pushes settled count=${batch.length}`);

  return batch.map((t) => t.uid);
}

async function enqueueWaveEvaluation(qid: string, wave: number): Promise<void> {
  const queue = getFunctions().taskQueue("evaluateWave");
  await queue.enqueue(
    { questionId: qid, wave },
    { scheduleDelaySeconds: WAVE_TIMEOUT_SECONDS }
  );
}

export async function enqueueQuestionWatchdog(qid: string): Promise<void> {
  const queue = getFunctions().taskQueue("questionWatchdog");
  await queue.enqueue(
    { questionId: qid },
    { scheduleDelaySeconds: INVITE_EXPIRY_SECONDS }
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
      photoUrls: question.photoUrls ?? [],
      studentUid: question.studentUid,
      studentName: question.studentName ?? "",
      studentImageURL: question.studentImageURL ?? "",
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
    photoUrls: string[];
    studentUid: string;
    studentName: string;
    studentImageURL: string;
    wave: number;
    conversationType: ConversationType;
  };

  await db.ref(`teacherInvites/${teacherUid}/${qid}`).set({
    topic: invitePayload.topic,
    text: invitePayload.text.slice(0, 300),
    photoUrls: invitePayload.photoUrls,
    studentName: invitePayload.studentName,
    studentImageURL: invitePayload.studentImageURL,
    expiresAt: Date.now() + INVITE_EXPIRY_SECONDS * 1000,
    wave: invitePayload.wave,
    conversationType: invitePayload.conversationType,
  });

  if (teacher.fcmToken) {
    await sendInvitePush({
      fcmToken: teacher.fcmToken,
      questionId: qid,
      topic: invitePayload.topic,
      studentName: invitePayload.studentName || invitePayload.studentUid,
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

/**
 * Fans a brand-new question out to its first wave of teachers.
 *
 * Called inline by `createQuestion` — that is the whole point. This used to run
 * only from the onCreate trigger below, which meant every question paid for
 * Eventarc delivery (~0.8s) plus a second Cloud Function's cold start (~2.8s)
 * before the first teacher was told anything. Running it in the function that
 * already has the question data skips both.
 *
 * `dispatchWave` is the claim: the caller flips it 0 → 1 and only the winner
 * fans out, so the trigger and this path can never double-invite.
 */
export async function dispatchFirstWave(qid: string, data: QuestionDoc): Promise<void> {
  logger.info(`[dispatch] starting dispatch for qid=${qid} topic=${data.topic}`);

  const qRef = firestore.collection("questions").doc(qid);
  const invited = await sendWave(qid, data, 1, new Set<string>());

  const update: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
  if (invited.length > 0) {
    update.alreadyInvited = FieldValue.arrayUnion(...invited);
  }
  await qRef.update(update);

  logger.info(`[dispatch] qid=${qid} wave 1 complete invitedNow=${invited.length}`);

  if (invited.length === 0) {
    // Keep the question searchable until the watchdog expires it. A teacher
    // can come online after creation and be invited by onTeacherStatusChange.
    // The scheduled wave evaluation also retries after transient presence
    // races (mobile clients can write status="online" just before subjects).
    logger.info(
      `[dispatch] qid=${qid} no eligible teachers in initial wave; keeping question in RTDB for backfill`
    );
  }

  await Promise.all([
    enqueueWaveEvaluation(qid, 1),
    enqueueQuestionWatchdog(qid),
  ]);
}

/**
 * Claims wave 1 for a question, returning false if someone already has it.
 *
 * `createQuestion` claims by writing `dispatchWave: 1` in the document it
 * creates, which costs nothing extra; the trigger below claims with this
 * transaction, which only ever succeeds if that inline path never ran.
 */
async function claimFirstWave(qid: string): Promise<QuestionDoc | null> {
  const qRef = firestore.collection("questions").doc(qid);

  return firestore.runTransaction(async (tx) => {
    const snap = await tx.get(qRef);
    if (!snap.exists) return null;

    const current = snap.data() as QuestionDoc;
    if (current.status !== "searching") return null;
    if ((current.dispatchWave ?? 0) >= 1) return null;

    tx.update(qRef, { dispatchWave: 1, updatedAt: FieldValue.serverTimestamp() });
    return current;
  });
}

// ─── dispatchQuestion — Firestore onCreate trigger ───────────────────────────
// FR-B-001, FR-B-002, FR-B-003
//
// A safety net, not the fast path. `createQuestion` normally dispatches wave 1
// itself and marks the question `dispatchWave: 1` as it writes it, so this
// trigger finds the wave already claimed and returns. It only does real work
// when that inline dispatch never happened — a createQuestion instance killed
// between writing the document and fanning it out.

export const dispatchQuestion = onDocumentCreated(
  { document: "questions/{qid}", ...HOT_PATH },
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

    // Deliberately not short-circuiting on `data.dispatchWave`: the event
    // payload is the document as it was created, which createQuestion always
    // stamps with 1, so it cannot show that an inline dispatch later failed and
    // handed the wave back. Only the transaction sees the current value. This
    // trigger is off the latency path now, so the extra read costs nothing that
    // matters.
    const claimed = await claimFirstWave(qid);
    if (!claimed) {
      logger.info(`[dispatch] qid=${qid} wave 1 claimed elsewhere, trigger standing down`);
      return;
    }

    logger.warn(`[dispatch] qid=${qid} inline dispatch did not run — recovering via trigger`);
    await dispatchFirstWave(qid, claimed);
  }
);

// ─── evaluateWave — Cloud Tasks handler ──────────────────────────────────────
// FR-B-003, FR-B-005
// Called WAVE_TIMEOUT_SECONDS after each wave. Fans out the next wave without
// cancelling earlier invites — all teachers have INVITE_EXPIRY_SECONDS to accept.

export const evaluateWave = onTaskDispatched<{ questionId: string; wave: number }>(
  {
    ...HOT_PATH,
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
      // No *new* eligible teachers for this wave — but earlier waves' invites
      // are still pending and haven't hit INVITE_EXPIRY_SECONDS yet. Do NOT
      // archive/delete them here; just stop fanning out further waves and let
      // those invites run their course (accept, decline, or the watchdog at
      // INVITE_EXPIRY_SECONDS). A teacher coming online later is still
      // backfilled via onTeacherStatusChange.
      logger.info(
        `[evaluateWave] qid=${qid} no new teachers for wave=${nextWave}, leaving ${(data.alreadyInvited ?? []).length} pending invite(s) untouched`
      );
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

// ─── questionWatchdog — Cloud Task ───────────────────────────────────────────
// Enqueued at question creation with INVITE_EXPIRY_SECONDS delay (90s).
// Fires regardless of wave outcome — absolute safety net ensuring no question
// stays "searching" longer than 90 seconds.

export const questionWatchdog = onTaskDispatched<{ questionId: string }>(
  {
    retryConfig: { maxAttempts: 2 },
    rateLimits: { maxConcurrentDispatches: 50 },
  },
  async (req) => {
    const { questionId: qid } = req.data;

    logger.info(`[watchdog] fired qid=${qid}`);

    const qSnap = await firestore.collection("questions").doc(qid).get();
    if (!qSnap.exists) {
      logger.info(`[watchdog] qid=${qid} not found, skipping`);
      return;
    }

    const data = qSnap.data() as QuestionDoc;
    if (data.status !== "searching") {
      logger.info(`[watchdog] qid=${qid} already ${data.status}, no action needed`);
      return;
    }

    logger.warn(`[watchdog] qid=${qid} still searching after ${INVITE_EXPIRY_SECONDS}s — archiving`);
    const archived = await archiveUnanswered(qid, data.alreadyInvited ?? []);

    if (archived) {
      const studentFcmToken = await db
        .ref(`users/${data.studentUid}/fcmToken`)
        .once("value")
        .then((s) => s.val() as string | null);
      if (studentFcmToken) {
        await sendNoMatchPush({ fcmToken: studentFcmToken, questionId: qid });
      }
    }
  }
);

// ─── onTeacherStatusChange — RTDB trigger ────────────────────────────────────
// Fires when teachers/{uid}/status is written. When a teacher comes online,
// immediately check for any searching questions they can be backfilled into.
// This is the counterpart to dispatchQuestion: it handles the case where a
// teacher goes online *after* a question is already waiting.

export const onTeacherStatusChange = onValueWritten(
  "teachers/{uid}/status",
  async (event) => {
    const uid = event.params.uid;
    const newStatus = event.data.after.val() as string | null;

    if (newStatus !== "online") return;

    logger.info(`[dispatch] teacher came online uid=${uid}, checking for waiting questions`);
    await backfillPendingQuestionsForTeacher(uid);
  }
);
