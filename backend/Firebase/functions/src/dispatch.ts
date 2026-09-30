import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { onValueWritten } from "firebase-functions/v2/database";
import { getFunctions } from "firebase-admin/functions";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { rankTeachers, subjectNarrows, teachesTopic } from "./scoring";
import { sendInvitePush, sendNoMatchPush } from "./fcm";
import {
  TeacherRecord,
  QuestionDoc,
  DispatchInviteDoc,
  WAVE_SIZES,
  WAVE_TIMEOUT_SECONDS,
  INVITE_EXPIRY_SECONDS,
  MIN_SUBJECT_TEACHERS,
  ConversationType,
  HOT_PATH,
  QuestionStruggle,
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

/** When a question's search ends: its own deadline, stamped by createQuestion
 *  from question_search_timeout_seconds, or INVITE_EXPIRY_SECONDS from now for
 *  one without, such as a demo question. Every invite runs until then. */
function searchEndsAtMillis(question: Pick<QuestionDoc, "searchEndsAt">): number {
  return question.searchEndsAt?.toMillis() ?? Date.now() + INVITE_EXPIRY_SECONDS * 1000;
}

/** Whole seconds from now until `millis`, at least one. */
function secondsUntil(millis: number): number {
  return Math.max(1, Math.ceil((millis - Date.now()) / 1000));
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
  const expiresAtMillis = searchEndsAtMillis(questionData);
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
    ...(questionData.struggle ? { struggle: questionData.struggle } : {}),
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
        teacherUid: uid,
        fcmToken: t.fcmToken,
        questionId: qid,
        topic: questionData.topic,
        studentName: questionData.studentName || questionData.studentUid,
        questionText: questionData.text,
        wave,
        ttlSeconds: secondsUntil(expiresAtMillis),
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

/** Arms the watchdog for when the question's search ends; see
 *  searchEndsAtMillis. */
export async function enqueueQuestionWatchdog(
  qid: string,
  question: Pick<QuestionDoc, "searchEndsAt"> = {}
): Promise<void> {
  const queue = getFunctions().taskQueue("questionWatchdog");
  await queue.enqueue(
    { questionId: qid },
    { scheduleDelaySeconds: secondsUntil(searchEndsAtMillis(question)) }
  );
}

/** Adds one teacher to a question's wave if that wave still has room.
 *
 *  `teachers` is the online roster, with this teacher in it: whether the
 *  question's subject narrows who may have it is decided on all of them (see
 *  subjectNarrows).
 *
 *  `targetWave` defaults to the wave the question is on now. A replacement for a
 *  withdrawn invite passes the withdrawn invite's own wave instead, so the slot
 *  is refilled where it was lost even if the question has since moved on. */
async function tryInviteTeacherForQuestionWave(
  teacherUid: string,
  teachers: Record<string, TeacherRecord>,
  qid: string,
  targetWave?: number
): Promise<boolean> {
  const teacher = teachers[teacherUid];
  if (!teacher) return false;
  const qRef = firestore.collection("questions").doc(qid);
  const inviteRef = qRef.collection("invites").doc(teacherUid);

  const result = await firestore.runTransaction(async (tx) => {
    const qSnap = await tx.get(qRef);
    if (!qSnap.exists) return { invited: false, reason: "question-not-found" };

    const question = qSnap.data() as QuestionDoc;
    if (question.status !== "searching") return { invited: false, reason: `status-${question.status}` };

    // Demo questions belong to the teacher who simulated them.
    if (question.isDemo && question.demoTeacherUid !== teacherUid) {
      return { invited: false, reason: "demo-question" };
    }

    const wave = targetWave ?? question.dispatchWave;
    if (!wave || wave < 1 || wave > WAVE_SIZES.length) {
      return { invited: false, reason: `invalid-wave-${wave ?? 0}` };
    }

    const narrow = subjectNarrows(teachers, question.topic);
    if (narrow && !teachesTopic(teacher, question.topic)) {
      return { invited: false, reason: "topic-mismatch" };
    }

    const alreadyInvited = new Set(question.alreadyInvited ?? []);
    if (alreadyInvited.has(teacherUid)) {
      return { invited: false, reason: "already-invited" };
    }

    const ranked = rankTeachers({ [teacherUid]: teacher }, question.topic, alreadyInvited, narrow);
    if (ranked.length === 0) {
      return { invited: false, reason: "not-eligible-now" };
    }

    const waveSize = WAVE_SIZES[wave - 1];
    const waveInviteQuery = qRef.collection("invites").where("wave", "==", wave);
    const waveInvitesSnap = await tx.get(waveInviteQuery);
    // A withdrawn invite no longer reaches anyone, so it does not hold a slot.
    const liveWaveInvites = waveInvitesSnap.docs.filter(
      (doc) => (doc.data() as DispatchInviteDoc).response !== "withdrawn"
    ).length;
    if (liveWaveInvites >= waveSize) {
      return { invited: false, reason: `wave-full-${liveWaveInvites}/${waveSize}` };
    }

    const now = Timestamp.now();
    const expiresAtMillis = searchEndsAtMillis(question);
    const expiresAt = Timestamp.fromMillis(expiresAtMillis);
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
      struggle: question.struggle,
      expiresAtMillis,
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
    struggle?: QuestionStruggle;
    expiresAtMillis: number;
  };

  await db.ref(`teacherInvites/${teacherUid}/${qid}`).set({
    topic: invitePayload.topic,
    text: invitePayload.text.slice(0, 300),
    photoUrls: invitePayload.photoUrls,
    studentName: invitePayload.studentName,
    studentImageURL: invitePayload.studentImageURL,
    expiresAt: invitePayload.expiresAtMillis,
    wave: invitePayload.wave,
    conversationType: invitePayload.conversationType,
    ...(invitePayload.struggle ? { struggle: invitePayload.struggle } : {}),
  });

  if (teacher.fcmToken) {
    await sendInvitePush({
      teacherUid,
      fcmToken: teacher.fcmToken,
      questionId: qid,
      topic: invitePayload.topic,
      studentName: invitePayload.studentName || invitePayload.studentUid,
      questionText: invitePayload.text,
      wave: invitePayload.wave,
      ttlSeconds: secondsUntil(invitePayload.expiresAtMillis),
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

  const teachers = { ...(await onlineTeachers()), [teacherUid]: teacher };
  let invitedCount = 0;
  for (const doc of orderedSearchingDocs) {
    const invited = await tryInviteTeacherForQuestionWave(teacherUid, teachers, doc.id);
    if (invited) {
      invitedCount += 1;
      break;
    }
  }

  logger.info(
    `[dispatch] backfill completed teacher=${teacherUid} invitedCount=${invitedCount} searched=${searchingSnap.size}`
  );
}

// ─── withdrawTeacherFromOtherQuestions ────────────────────────────────────────
// Two students asking at once are both sent the same top-ranked teachers. When
// one of those teachers accepts, they are no longer available to the other
// student, whose question would otherwise sit with one fewer live invite than
// its wave promised. This takes the busy teacher's other pending invites back and
// hands each slot to the next-best teacher who has not seen that question yet.

/** Marks the teacher's invite on `qid` withdrawn, if it is still pending on a
 *  question that is still searching. Returns what the refill needs, or null. */
async function withdrawPendingInvite(
  teacherUid: string,
  qid: string
): Promise<{ wave: number; topic: string; alreadyInvited: string[] } | null> {
  const qRef = firestore.collection("questions").doc(qid);
  const inviteRef = qRef.collection("invites").doc(teacherUid);

  return firestore.runTransaction(async (tx) => {
    const [qSnap, invSnap] = await Promise.all([tx.get(qRef), tx.get(inviteRef)]);
    if (!qSnap.exists || !invSnap.exists) return null;

    const question = qSnap.data() as QuestionDoc;
    const invite = invSnap.data() as DispatchInviteDoc;
    if (question.status !== "searching" || invite.response !== "pending") return null;

    tx.update(inviteRef, { response: "withdrawn" });
    return {
      wave: invite.wave,
      topic: question.topic,
      alreadyInvited: question.alreadyInvited ?? [],
    };
  });
}

export async function withdrawTeacherFromOtherQuestions(
  teacherUid: string,
  acceptedQid: string
): Promise<void> {
  // teacherInvites/{uid} is exactly the set of cards on the teacher's
  // dashboard, which is the set of invites that still need taking back.
  const pendingSnap = await db.ref(`teacherInvites/${teacherUid}`).once("value");
  const pending = (pendingSnap.val() as Record<string, unknown> | null) ?? {};
  const otherQids = Object.keys(pending).filter((qid) => qid !== acceptedQid);

  if (otherQids.length === 0) return;

  logger.info(
    `[dispatch] withdrawing teacher=${teacherUid} from ${otherQids.length} other question(s) after accepting qid=${acceptedQid}`
  );

  await Promise.all(
    otherQids.map(async (qid) => {
      const withdrawn = await withdrawPendingInvite(teacherUid, qid);
      await db.ref(`teacherInvites/${teacherUid}/${qid}`).remove();
      if (!withdrawn) return;

      const teachers = await onlineTeachers();
      const exclude = new Set([...withdrawn.alreadyInvited, teacherUid]);
      const ranked = rankTeachers(teachers, withdrawn.topic, exclude);

      for (const { uid } of ranked) {
        if (await tryInviteTeacherForQuestionWave(uid, teachers, qid, withdrawn.wave)) {
          logger.info(
            `[dispatch] qid=${qid} wave=${withdrawn.wave} slot of teacher=${teacherUid} refilled by teacher=${uid}`
          );
          return;
        }
      }

      logger.info(
        `[dispatch] qid=${qid} wave=${withdrawn.wave} slot of teacher=${teacherUid} left empty, no eligible replacement`
      );
    })
  );
}

// ─── applyQuestionDetails ────────────────────────────────────────────────────
// The student names the subject, says why they are stuck and how they would
// like to start while the search runs (see updateQuestion in ./questions).
// Every teacher still holding the question sees the new details on its card.
// A subject a teacher does not teach takes the question back from them, as an
// accepted question does (see withdrawTeacherFromOtherQuestions above), and
// their place in the wave goes to the best teacher who does teach it. Later
// waves read the question as it now is, so they go only to such teachers too.
// All of that only while at least MIN_SUBJECT_TEACHERS teachers who could take
// the question teach the subject (see subjectNarrows): with fewer, nobody is
// dropped, and later waves go to every teacher, those who teach it first.

export interface QuestionDetails {
  topic?: string;
  struggle?: QuestionStruggle;
  conversationType?: ConversationType;
}

/** Called once the question document already carries `details`. */
export async function applyQuestionDetails(
  qid: string,
  details: QuestionDetails
): Promise<{ withdrawn: string[]; refilled: string[] }> {
  const qRef = firestore.collection("questions").doc(qid);
  const pendingSnap = await qRef.collection("invites").where("response", "==", "pending").get();
  const pending = pendingSnap.docs.map((doc) => doc.data() as DispatchInviteDoc);

  // The teachers the question no longer fits: those who do not teach its
  // new subject, while enough others do.
  let dropped: DispatchInviteDoc[] = [];
  const topic = details.topic;
  if (topic !== undefined && pending.length > 0) {
    if (subjectNarrows(await onlineTeachers(), topic)) {
      const records = await Promise.all(
        pending.map((invite) => db.ref(`teachers/${invite.teacherUid}`).once("value"))
      );
      dropped = pending.filter((_, index) => {
        const teacher = records[index].val() as TeacherRecord | null;
        return !teacher || !teachesTopic(teacher, topic);
      });
    } else {
      logger.info(
        `[dispatch] qid=${qid} fewer than ${MIN_SUBJECT_TEACHERS} available teachers teach topic=${topic}; keeping all ${pending.length} invited`
      );
    }
  }
  const droppedUids = new Set(dropped.map((invite) => invite.teacherUid));
  const kept = pending.filter((invite) => !droppedUids.has(invite.teacherUid));

  // Written through transactions that stand down on a missing node, so a
  // card cleared meanwhile — the teacher declined, or the question was taken —
  // is not brought back without its question.
  const patchIfPresent = (current: unknown) =>
    current && typeof current === "object"
      ? { ...(current as Record<string, unknown>), ...details }
      : undefined;
  await Promise.all([
    db.ref(`questions/${qid}`).transaction(patchIfPresent),
    ...kept.map((invite) => db.ref(`teacherInvites/${invite.teacherUid}/${qid}`).transaction(patchIfPresent)),
    ...(details.conversationType
      ? kept.map((invite) =>
        qRef.collection("invites").doc(invite.teacherUid).update({
          conversationType: details.conversationType,
        })
      )
      : []),
  ]);

  // One at a time, so a replacement found for one slot is already invited —
  // and so excluded — when the next slot looks for its own.
  const withdrawn: string[] = [];
  const refilled: string[] = [];
  for (const invite of dropped) {
    const taken = await withdrawPendingInvite(invite.teacherUid, qid);
    await db.ref(`teacherInvites/${invite.teacherUid}/${qid}`).remove();
    if (!taken) continue;
    withdrawn.push(invite.teacherUid);

    const teachers = await onlineTeachers();
    const exclude = new Set([...taken.alreadyInvited, invite.teacherUid]);
    const ranked = rankTeachers(teachers, taken.topic, exclude);
    for (const { uid } of ranked) {
      if (await tryInviteTeacherForQuestionWave(uid, teachers, qid, taken.wave)) {
        refilled.push(uid);
        break;
      }
    }
  }

  logger.info(
    `[dispatch] qid=${qid} details applied keys=${Object.keys(details).join(",")} kept=${kept.length} withdrawn=${withdrawn.length} refilled=${refilled.length}`
  );
  return { withdrawn, refilled };
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
    enqueueQuestionWatchdog(qid, data),
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

    // Simulated questions (demo-student service) are already delivered to the
    // one teacher who asked for them. Skip the waves so no real teacher is
    // paged by a demo, and arm the watchdog here: demoStudent writes the
    // document itself with dispatchWave already 1, so it never goes through
    // the inline path, and claimFirstWave below would stand down without
    // arming one — leaving the demo question searching forever.
    if (data.isDemo) {
      logger.info(
        `[dispatch] qid=${qid} isDemo — skipping waves, invited teacher=${data.demoTeacherUid ?? "unknown"}`
      );
      await enqueueQuestionWatchdog(qid);
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
// cancelling earlier invites — every teacher can accept until the search ends.

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

    // Invites from this wave remain pending — every teacher can accept until
    // the search ends. Only fan out the next wave so more teachers are
    // notified sooner.
    const nextWave = wave + 1;

    // FR-B-005: after the last wave the question stays with the teachers who
    // have it, and with any who come online (onTeacherStatusChange), until its
    // search ends. The watchdog declares it unanswered then. It used to be
    // declared unanswered here, 36 seconds in, whatever the search's length.
    if (nextWave > WAVE_SIZES.length) {
      logger.info(
        `[evaluateWave] last wave reached qid=${qid} currentWave=${wave}; waiting for the search to end`
      );
      return;
    }

    // Fan out next wave
    const alreadyInvited = new Set<string>(data.alreadyInvited ?? []);
    const invited = await sendWave(qid, data, nextWave, alreadyInvited);

    if (invited.length === 0) {
      // No *new* eligible teachers for this wave — but earlier waves' invites
      // are still pending until the search ends. Do NOT archive/delete them
      // here; just stop fanning out further waves and let those invites run
      // their course (accept, decline, or the watchdog when the search ends).
      // A teacher coming online later is still backfilled via
      // onTeacherStatusChange.
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
// Enqueued at question creation for when its search ends (`searchEndsAt`, from
// question_search_timeout_seconds; INVITE_EXPIRY_SECONDS without one). Fires
// regardless of wave outcome, and is what declares a question nobody took
// unanswered.

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

    logger.warn(`[watchdog] qid=${qid} still searching when its search ended — archiving`);
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
    // Every keep-alive re-sends "online" (see ./keepAlive). Only a teacher
    // coming online has questions to be backfilled into.
    if (event.data.before.val() === "online") return;

    logger.info(`[dispatch] teacher came online uid=${uid}, checking for waiting questions`);
    await backfillPendingQuestionsForTeacher(uid);
  }
);
