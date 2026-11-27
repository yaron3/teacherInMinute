// ─── Stale live questions and lessons ────────────────────────────────────────
//
// A question or lesson whose ending task never ran (a failed Cloud Task, a
// deploy mid-lesson, an emulator-era record) stays `searching`, `accepted` or
// `in_progress` for good. It shows as an active lesson in the admin console,
// blocks deleting either participant's account, and keeps the demo-data
// cleanup from touching it.
//
// The admin console lists them and closes the ones ticked. Closing is a
// write-off, the way endAbandonedLesson (./lessons) ends a lesson nobody
// joined: nobody is charged or paid. It never settles billing the way a lesson
// ending normally does: that reads the lesson's live RTDB node, which a record
// this old no longer has, and would bill a student months later.
//
// Every record is read again and re-checked before it is closed, so one that
// came back to life, or was ended in between, is skipped.

import * as admin from "firebase-admin";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";
import { readDemoUserUids } from "./demoUsers";
import { releaseTeacherBusy } from "./busy";

/** Far past anything legitimate: a lesson is force-ended at 30 minutes, and a
 *  search or a lesson that never connected gives up within minutes. */
export const STALE_LIVE_AFTER_MS = 24 * 3600 * 1000;
export const STALE_LIVE_CLOSE_MAX = 100;

const LIVE_QUESTION_STATUSES = ["searching", "accepted", "in_progress"];

export type StaleLiveKind = "question" | "lesson";

export interface StaleLiveRef {
  kind: StaleLiveKind;
  id: string;
}

export interface StaleLiveItem extends StaleLiveRef {
  status: string;
  /** For a lesson: its question's status, or null if the question is gone. */
  questionStatus: string | null;
  questionId: string | null;
  lastActivityAt: number | null;
  studentUid: string | null;
  studentName: string | null;
  teacherUid: string | null;
  teacherName: string | null;
  /** Every participant is a demo user. */
  demo: boolean;
  topic: string | null;
}

export type StaleLiveResult = { status: "closed" | "skipped" | "failed"; reason?: string };

export function toMs(value: unknown): number | null {
  if (!value) return null;
  if (typeof value === "number") return value < 1e12 ? value * 1000 : value;
  const obj = value as { toMillis?: () => number; _seconds?: number; seconds?: number };
  if (typeof obj.toMillis === "function") return obj.toMillis();
  if (typeof obj._seconds === "number") return obj._seconds * 1000;
  if (typeof obj.seconds === "number") return obj.seconds * 1000;
  return null;
}

/** The latest sign of life on a question or lesson record. */
export function lastActivityMs(data: Record<string, unknown>): number | null {
  const times = ["updatedAt", "acceptedAt", "startedAt", "createdAt"]
    .map((f) => toMs(data[f]))
    .filter((t): t is number => t !== null);
  return times.length ? Math.max(...times) : null;
}

/** True when the record has shown no sign of life for STALE_LIVE_AFTER_MS. A
 *  record with no timestamps at all is stale too: nothing can end it. */
export function isStale(data: Record<string, unknown>, nowMs: number): boolean {
  const last = lastActivityMs(data);
  return last === null || nowMs - last >= STALE_LIVE_AFTER_MS;
}

export function isLiveQuestion(data: Record<string, unknown> | undefined): boolean {
  return !!data && LIVE_QUESTION_STATUSES.includes(String(data.status ?? ""));
}

function str(value: unknown): string | null {
  return typeof value === "string" && value ? value : null;
}

/** Every stale live question and lesson in the project. */
export async function buildStaleLivePreview(nowMs = Date.now()): Promise<StaleLiveItem[]> {
  const firestore = admin.firestore();
  const [demoUids, ...snaps] = await Promise.all([
    readDemoUserUids(),
    ...LIVE_QUESTION_STATUSES.map((s) => firestore.collection("questions").where("status", "==", s).get()),
  ]);
  const lessonSnap = await firestore.collection("lessons").where("status", "==", "in_progress").get();

  const items: StaleLiveItem[] = [];
  for (const snap of snaps as FirebaseFirestore.QuerySnapshot[]) {
    for (const doc of snap.docs) {
      const q = doc.data();
      if (!isStale(q, nowMs)) continue;
      items.push({
        kind: "question",
        id: doc.id,
        status: String(q.status),
        questionStatus: String(q.status),
        questionId: doc.id,
        lastActivityAt: lastActivityMs(q),
        studentUid: str(q.studentUid),
        studentName: str(q.studentName),
        teacherUid: str(q.acceptedByTeacher) ?? str(q.demoTeacherUid),
        teacherName: null,
        demo: false,
        topic: str(q.topic),
      });
    }
  }
  const listedQuestions = new Set(items.map((i) => i.id));
  for (const doc of lessonSnap.docs) {
    const l = doc.data();
    if (!isStale(l, nowMs)) continue;
    const questionId = str(l.questionId);
    // A lesson whose question is listed is closed along with it.
    if (questionId && listedQuestions.has(questionId)) continue;
    const q = questionId ? (await firestore.collection("questions").doc(questionId).get()).data() : undefined;
    items.push({
      kind: "lesson",
      id: doc.id,
      status: String(l.status),
      questionStatus: q ? String(q.status ?? "") : null,
      questionId,
      lastActivityAt: lastActivityMs(l),
      studentUid: str(l.studentUid),
      studentName: str(q?.studentName),
      teacherUid: str(l.teacherUid),
      teacherName: null,
      demo: false,
      topic: str(q?.topic),
    });
  }

  const uids = [...new Set(items.flatMap((i) => [i.studentUid, i.teacherUid]).filter((u): u is string => !!u))];
  const users = uids.length ? await firestore.getAll(...uids.map((u) => firestore.collection("users").doc(u))) : [];
  const names = new Map(users.map((u) => [u.id, str(u.data()?.fullName)]));
  for (const item of items) {
    if (item.studentUid) item.studentName = names.get(item.studentUid) ?? item.studentName;
    if (item.teacherUid) item.teacherName = names.get(item.teacherUid) ?? null;
    const parties = [item.studentUid, item.teacherUid].filter((u): u is string => !!u);
    item.demo = parties.length > 0 && parties.every((u) => demoUids.has(u));
  }
  items.sort((a, b) => (b.lastActivityAt ?? 0) - (a.lastActivityAt ?? 0));
  return items;
}

/** What a written-off record's money fields read: nothing charged, nothing paid. */
const ZERO_BILLING = { billedSeconds: 0, totalCents: 0, cost: 0, teacherEarnings: 0 };

async function lessonRefsForQuestion(questionId: string, lessonId: unknown): Promise<FirebaseFirestore.DocumentReference[]> {
  const firestore = admin.firestore();
  const refs = new Map<string, FirebaseFirestore.DocumentReference>();
  if (typeof lessonId === "string" && lessonId) refs.set(lessonId, firestore.collection("lessons").doc(lessonId));
  const snap = await firestore.collection("lessons").where("questionId", "==", questionId).get();
  for (const d of snap.docs) refs.set(d.id, d.ref);
  return [...refs.values()];
}

async function closeStaleQuestion(id: string, nowMs: number): Promise<StaleLiveResult> {
  const firestore = admin.firestore();
  const db = admin.database();
  const ref = firestore.collection("questions").doc(id);

  // The live node is written all through a lesson; a recent write there means
  // the lesson is running whatever the Firestore record says.
  const live = (await db.ref(`questions/${id}`).once("value")).val() as Record<string, unknown> | null;
  const liveAt = live ? toMs(live.updatedAt) : null;
  if (liveAt !== null && nowMs - liveAt < STALE_LIVE_AFTER_MS) return { status: "skipped", reason: "active in RTDB" };

  let before: Record<string, unknown> | undefined;
  const reason = await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return "already gone";
    const q = snap.data() ?? {};
    if (!isLiveQuestion(q)) return `already ${q.status ?? "ended"}`;
    if (!isStale(q, nowMs)) return "active again";
    before = q;
    // A search that never found a teacher ends the way the search watchdog
    // ends one (./dispatch); a claimed one is written off.
    const fields =
      q.status === "searching"
        ? { status: "unanswered" }
        : { status: "cancelled", ...ZERO_BILLING, durationSeconds: 0 };
    tx.update(ref, {
      ...fields,
      endedBy: "system",
      endedReason: "stale_closeout",
      endedAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return null;
  });
  if (reason || !before) return { status: "skipped", reason: reason ?? "unchanged" };

  for (const invite of await ref.collection("invites").listDocuments()) {
    await db.ref(`teacherInvites/${invite.id}/${id}`).remove();
  }
  await db.ref(`questions/${id}`).remove();
  await db.ref(`lessonPresence/${id}`).remove();

  const teacher = str(before.acceptedByTeacher);
  if (teacher) {
    await releaseTeacherBusy(teacher, id).catch((error) => {
      logger.error(`[staleLive] failed releasing teacher=${teacher} qid=${id}`, error);
    });
  }

  for (const lessonRef of await lessonRefsForQuestion(id, before.lessonId)) {
    await firestore.runTransaction(async (tx) => {
      const lesson = await tx.get(lessonRef);
      if (!lesson.exists || lesson.data()?.status !== "in_progress") return;
      tx.update(lessonRef, {
        status: "completed",
        endedBy: "system",
        endedAt: FieldValue.serverTimestamp(),
        ...ZERO_BILLING,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
  }

  logger.warn(`[staleLive] closed question qid=${id} was=${before.status}`);
  return { status: "closed" };
}

async function closeStaleLesson(id: string, nowMs: number): Promise<StaleLiveResult> {
  const firestore = admin.firestore();
  const ref = firestore.collection("lessons").doc(id);
  const snap = await ref.get();
  if (!snap.exists) return { status: "skipped", reason: "already gone" };
  const questionId = str(snap.data()?.questionId);

  // A lesson whose question is still live goes with the question.
  if (questionId) {
    const question = (await firestore.collection("questions").doc(questionId).get()).data();
    if (isLiveQuestion(question)) return closeStaleQuestion(questionId, nowMs);
  }

  let teacher: string | null = null;
  const reason = await firestore.runTransaction(async (tx) => {
    const lessonSnap = await tx.get(ref);
    if (!lessonSnap.exists) return "already gone";
    const lesson = lessonSnap.data() ?? {};
    if (lesson.status !== "in_progress") return `already ${lesson.status ?? "ended"}`;
    if (!isStale(lesson, nowMs)) return "active again";
    const question = questionId
      ? (await tx.get(firestore.collection("questions").doc(questionId))).data()
      : undefined;
    if (isLiveQuestion(question)) return "its question is live again";
    teacher = str(lesson.teacherUid);
    // The question already ended and holds the settled figures; the lesson
    // record takes the same ones rather than contradicting it.
    const settled =
      question?.status === "completed"
        ? {
            billedSeconds: Number(question.billedSeconds) || 0,
            totalCents: Number(question.totalCents) || 0,
            cost: Number(question.cost) || 0,
            teacherEarnings: Number(question.teacherEarnings) || 0,
          }
        : ZERO_BILLING;
    tx.update(ref, {
      status: "completed",
      endedBy: "system",
      endedAt: question?.endedAt instanceof Timestamp ? question.endedAt : FieldValue.serverTimestamp(),
      ...settled,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return null;
  });
  if (reason) return { status: "skipped", reason };

  if (teacher && questionId) {
    const t: string = teacher;
    await releaseTeacherBusy(t, questionId).catch((error) => {
      logger.error(`[staleLive] failed releasing teacher=${t} qid=${questionId}`, error);
    });
  }
  logger.warn(`[staleLive] closed lesson lid=${id} qid=${questionId ?? "none"}`);
  return { status: "closed" };
}

/** Closes one record after checking it is still live and still stale. */
export async function closeStaleLiveItem(ref: StaleLiveRef, nowMs = Date.now()): Promise<StaleLiveResult> {
  return ref.kind === "question" ? closeStaleQuestion(ref.id, nowMs) : closeStaleLesson(ref.id, nowMs);
}

export function isStaleLiveRef(value: unknown): value is StaleLiveRef {
  const v = value as StaleLiveRef | null;
  return (
    !!v &&
    (v.kind === "question" || v.kind === "lesson") &&
    typeof v.id === "string" &&
    v.id.length > 0 &&
    !v.id.includes("/")
  );
}
