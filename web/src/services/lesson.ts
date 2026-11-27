import {
  onChildAdded,
  remove,
  update,
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

// Either side of a live lesson, speaking the same protocol as
// ChatSessionService on iOS and Android, so a web student or teacher looks to
// the other side exactly like one on a phone. Every write names the writer's
// role; every read of "the other side" names theirs.

export const LIVEKIT_URL = "wss://teacher-in-a-moment-qx23966i.livekit.cloud";

export type Role = "student" | "teacher";
export const peerOf = (role: Role): Role => (role === "student" ? "teacher" : "student");

/** Statuses that mean the lesson is over (ChatSessionService's terminal set). */
const TERMINAL = new Set(["cancelled", "canceled", "declined", "rejected", "ended", "expired", "completed", "unanswered"]);

export interface LiveQuestion {
  status: string;
  teacherId: string;
  teacherName: string;
  studentId: string;
  studentName: string;
  startedAt: number;
  /** The lesson's shared medium; either side may change it while it runs. */
  conversationType: string;
  questionText: string;
  /** When the student's minutes run out, epoch ms; 0 when not published. */
  minutesDeadlineAt: number;
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
      studentId: String(d.studentUid ?? d.studentId ?? ""),
      studentName: String(d.studentName ?? ""),
      startedAt: Number(d.startedAt ?? 0),
      conversationType: String(d.conversationType ?? "text"),
      questionText: String(d.text ?? ""),
      minutesDeadlineAt: Number(d.minutesDeadlineAt ?? 0),
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

export async function sendMessage(questionId: string, role: Role, uid: string, text: string): Promise<void> {
  await set(push(ref(database, `questions/${questionId}/messages`)), {
    text: text.trim(),
    senderUid: uid,
    senderRole: role,
    createdAt: Date.now(),
    kind: "text",
  });
}

// ─── Presence: lessonPresence/{qid}/{role} ───────────────────────────────────
// One entry per database connection, removed by the server when it drops, and
// `lostAt` stamped then. The lesson is billed up to the first side to leave or
// to lose its connection and not come back.

export function keepPresence(questionId: string, role: Role): () => Promise<void> {
  const side = ref(database, `lessonPresence/${questionId}/${role}`);
  const lostAt = ref(database, `lessonPresence/${questionId}/${role}/lostAt`);
  const stopConnected = onValue(ref(database, ".info/connected"), (snap) => {
    if (snap.val() !== true) return;
    const entry = push(ref(database, `lessonPresence/${questionId}/${role}/connections`));
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

export async function markLeft(questionId: string, role: Role): Promise<void> {
  await set(ref(database, `lessonPresence/${questionId}/${role}/leftAt`), serverTimestamp());
}

/** Calls back once the other side has left the lesson. */
export function watchPeerGone(questionId: string, peer: Role, onGone: () => void): Unsubscribe {
  return onValue(ref(database, `lessonPresence/${questionId}/${peer}`), (snap) => {
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

// ─── Shared medium and media signals ──────────────────────────────────────────
// `conversationType` is the lesson's medium; `mediaPending/{role}` says a side
// is staying without audio after the other added it; `mediaState/{role}` is
// one number: 1 = microphone muted, 2 = camera off (MediaDeviceState.bits).

export async function setConversationType(questionId: string, type: string): Promise<void> {
  await set(ref(database, `questions/${questionId}/conversationType`), type);
}

export async function setMediaPending(questionId: string, role: Role, pending: boolean): Promise<void> {
  await set(ref(database, `questions/${questionId}/mediaPending/${role}`), pending);
}

export async function setMediaState(questionId: string, role: Role, micMuted: boolean, cameraOff: boolean): Promise<void> {
  await set(ref(database, `questions/${questionId}/mediaState/${role}`), (micMuted ? 1 : 0) | (cameraOff ? 2 : 0));
}

export interface PeerMedia {
  pending: boolean;
  micMuted: boolean;
  cameraOff: boolean;
}

/** The other side's media signals. */
export function watchPeerMedia(questionId: string, peer: Role, onChange: (m: PeerMedia) => void): Unsubscribe {
  let pending = false;
  let bits = 0;
  const emit = () => onChange({ pending, micMuted: (bits & 1) !== 0, cameraOff: (bits & 2) !== 0 });
  const a = onValue(ref(database, `questions/${questionId}/mediaPending/${peer}`), (s) => {
    pending = s.val() === true;
    emit();
  });
  const b = onValue(ref(database, `questions/${questionId}/mediaState/${peer}`), (s) => {
    bits = Number(s.val() ?? 0);
    emit();
  });
  return () => {
    a();
    b();
  };
}

// ─── Whiteboard: questions/{qid}/board ────────────────────────────────────────
// Strokes are point lists on a 2000 × 2000 logical board (WhiteboardView's
// logicalSize); shapes travel as the points that draw them. Colour is not sent:
// each side colours a stroke by whether it is its own.

export const BOARD_SIZE = 2000;

export interface BoardPoint {
  x: number;
  y: number;
}

export interface BoardStroke {
  id: string;
  points: BoardPoint[];
  createdAt: number;
  senderUid: string;
}

export interface BoardViewport {
  x: number;
  y: number;
  width: number;
  height: number;
}

export function watchBoard(questionId: string, onChange: (strokes: BoardStroke[]) => void): Unsubscribe {
  return onValue(ref(database, `questions/${questionId}/board/strokes`), (snap) => {
    const strokes: BoardStroke[] = [];
    snap.forEach((child) => {
      const d = child.val();
      const raw = Array.isArray(d?.points) ? d.points : Object.values(d?.points ?? {});
      const points = (raw as { x?: unknown; y?: unknown }[])
        .map((p) => ({ x: Number(p?.x), y: Number(p?.y) }))
        .filter((p) => Number.isFinite(p.x) && Number.isFinite(p.y));
      if (points.length) {
        strokes.push({ id: child.key ?? "", points, createdAt: Number(d?.createdAt ?? 0), senderUid: String(d?.senderUid ?? "") });
      }
    });
    strokes.sort((a, b) => a.createdAt - b.createdAt);
    onChange(strokes);
  });
}

export async function sendStroke(questionId: string, uid: string, points: BoardPoint[]): Promise<string> {
  const entry = push(ref(database, `questions/${questionId}/board/strokes`));
  await set(entry, { points: points.map(({ x, y }) => ({ x, y })), createdAt: Date.now(), senderUid: uid });
  return entry.key ?? "";
}

/** Removes the strokes in one write, so an eraser sweep lands together. */
export async function eraseStrokes(questionId: string, ids: string[]): Promise<void> {
  if (!ids.length) return;
  await update(ref(database, `questions/${questionId}/board/strokes`), Object.fromEntries(ids.map((id) => [id, null])));
}

/** The teacher's clear: every stroke goes (WhiteboardView.canClearBoard). */
export async function clearBoard(questionId: string): Promise<void> {
  await remove(ref(database, `questions/${questionId}/board/strokes`));
}

export async function updateViewport(questionId: string, role: Role, v: BoardViewport): Promise<void> {
  await set(ref(database, `questions/${questionId}/board/viewports/${role}`), { ...v, updatedAt: Date.now() });
}

export function watchPeerViewport(questionId: string, peer: Role, onChange: (v: BoardViewport | null) => void): Unsubscribe {
  return onValue(ref(database, `questions/${questionId}/board/viewports/${peer}`), (snap) => {
    const d = snap.val();
    const v = d && { x: Number(d.x), y: Number(d.y), width: Number(d.width), height: Number(d.height) };
    onChange(v && [v.x, v.y, v.width, v.height].every(Number.isFinite) && v.width > 0 ? v : null);
  });
}

// ─── Leave to draw: questions/{qid}/boardPermission ───────────────────────────
// The student asks with `requested` under a fresh requestId; the teacher answers
// `granted` or `declined` under the same id (BoardDrawPermission).

export interface BoardPermission {
  status: "requested" | "granted" | "declined";
  requestId: string;
}

export function watchBoardPermission(questionId: string, onChange: (p: BoardPermission | null) => void): Unsubscribe {
  return onValue(ref(database, `questions/${questionId}/boardPermission`), (snap) => {
    const d = snap.val();
    const ok = d && ["requested", "granted", "declined"].includes(d.status) && typeof d.requestId === "string" && d.requestId;
    onChange(ok ? { status: d.status, requestId: d.requestId } : null);
  });
}

export async function requestBoardPermission(questionId: string, requestId: string): Promise<void> {
  await set(ref(database, `questions/${questionId}/boardPermission`), {
    status: "requested",
    requestId,
    updatedAt: serverTimestamp(),
  });
}

/** The teacher answers a student's ask under the same request id. */
export async function answerBoardPermission(questionId: string, requestId: string, approve: boolean): Promise<void> {
  await set(ref(database, `questions/${questionId}/boardPermission`), {
    status: approve ? "granted" : "declined",
    requestId,
    updatedAt: serverTimestamp(),
  });
}
