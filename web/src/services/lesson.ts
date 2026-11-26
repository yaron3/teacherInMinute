import {
  onChildAdded,
  onDisconnect,
  onValue,
  push,
  ref,
  serverTimestamp,
  set,
  type Unsubscribe,
} from "firebase/database";
import { httpsCallable } from "firebase/functions";
import { database, functions } from "./firebase";

// The student's side of a live lesson, speaking the same protocol as
// ChatSessionService on iOS and Android, so a teacher on either app sees a web
// student exactly as they would see one on a phone.

export const LIVEKIT_URL = "wss://teacher-in-a-moment-qx23966i.livekit.cloud";

const ROLE = "student";

/** Statuses that mean the lesson is over (ChatSessionService's terminal set). */
const TERMINAL = new Set(["cancelled", "canceled", "declined", "rejected", "ended", "expired", "completed", "unanswered"]);

export interface LiveQuestion {
  status: string;
  teacherId: string;
  teacherName: string;
  startedAt: number;
  conversationType: string;
  isOver: boolean;
}

export interface ChatMessage {
  id: string;
  text: string;
  senderUid: string;
  senderRole: string;
  createdAt: number;
  kind: string;
}

/** Follows `questions/{qid}`. `null` once the row is gone. */
export function watchQuestion(questionId: string, onChange: (q: LiveQuestion | null) => void): Unsubscribe {
  return onValue(ref(database, `questions/${questionId}`), (snap) => {
    const d = snap.val();
    if (!d || !d.status) return onChange(null);
    const status = String(d.status);
    onChange({
      status,
      teacherId: String(d.teacherId ?? d.teacherUid ?? ""),
      teacherName: String(d.teacherName ?? ""),
      startedAt: Number(d.startedAt ?? 0),
      conversationType: String(d.conversationType ?? "text"),
      isOver: TERMINAL.has(status),
    });
  });
}

export function watchMessages(questionId: string, onMessage: (m: ChatMessage) => void): Unsubscribe {
  return onChildAdded(ref(database, `questions/${questionId}/messages`), (snap) => {
    const d = snap.val();
    if (typeof d?.text !== "string" || typeof d?.senderUid !== "string") return;
    onMessage({
      id: snap.key ?? "",
      text: d.text,
      senderUid: d.senderUid,
      senderRole: String(d.senderRole ?? "student"),
      createdAt: Number(d.createdAt ?? 0),
      kind: String(d.kind ?? "text"),
    });
  });
}

export async function sendMessage(questionId: string, uid: string, text: string): Promise<void> {
  await set(push(ref(database, `questions/${questionId}/messages`)), {
    text: text.trim(),
    senderUid: uid,
    senderRole: ROLE,
    createdAt: Date.now(),
    kind: "text",
  });
}

// ─── Presence: lessonPresence/{qid}/student ───────────────────────────────────
// One entry per database connection, removed by the server when it drops, and
// `lostAt` stamped then. The lesson is billed up to the first side to leave or
// to lose its connection and not come back.

export function keepPresence(questionId: string): () => Promise<void> {
  const side = ref(database, `lessonPresence/${questionId}/${ROLE}`);
  const lostAt = ref(database, `lessonPresence/${questionId}/${ROLE}/lostAt`);
  const stopConnected = onValue(ref(database, ".info/connected"), (snap) => {
    if (snap.val() !== true) return;
    const entry = push(ref(database, `lessonPresence/${questionId}/${ROLE}/connections`));
    onDisconnect(entry).remove();
    onDisconnect(lostAt).set(serverTimestamp());
    set(entry, true).catch((e) => console.error("[lesson] presence write failed", e));
  });
  // Stops keeping presence as the session ends online: the handlers are
  // cancelled so a later drop writes nothing. The entry itself stays; the
  // backend clears the lesson's presence as it settles it.
  return async () => {
    stopConnected();
    await onDisconnect(side).cancel();
  };
}

export async function markLeft(questionId: string): Promise<void> {
  await set(ref(database, `lessonPresence/${questionId}/${ROLE}/leftAt`), serverTimestamp());
}

/** Calls back once the teacher has left or lost the lesson. */
export function watchTeacherGone(questionId: string, onGone: () => void): Unsubscribe {
  return onValue(ref(database, `lessonPresence/${questionId}/teacher`), (snap) => {
    const d = snap.val();
    if (d?.leftAt) onGone();
  });
}

// ─── Callables ────────────────────────────────────────────────────────────────

export async function startLesson(questionId: string, ready: boolean): Promise<{ started: boolean }> {
  const result = await httpsCallable<object, { lessonId?: string; started?: boolean }>(functions, "startLesson")({
    questionId,
    ready,
  });
  return { started: result.data.started ?? !!result.data.lessonId };
}

export async function endLesson(questionId: string): Promise<{ lessonSeconds?: number }> {
  const result = await httpsCallable<object, { lessonSeconds?: number }>(functions, "endLesson")({ questionId });
  return result.data;
}

export async function rateTeacher(questionId: string, teacherId: string, rating: number, comment: string): Promise<void> {
  const data: Record<string, unknown> = { questionId, teacherId, rating };
  if (comment.trim()) data.comment = comment.trim();
  await httpsCallable(functions, "rateTeacher")(data);
}

/** The LiveKit credentials, when createQuestion's own mint failed. */
export async function fetchMediaCredentials(questionId: string): Promise<{ room: string; token: string } | null> {
  const result = await httpsCallable<object, { liveKitRoom?: string; liveKitToken?: string }>(
    functions,
    "getQuestionStatus",
  )({ questionId });
  const { liveKitRoom, liveKitToken } = result.data;
  return liveKitRoom && liveKitToken ? { room: liveKitRoom, token: liveKitToken } : null;
}
