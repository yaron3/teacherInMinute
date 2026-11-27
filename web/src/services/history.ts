import { doc, getDoc } from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import { firestore, functions } from "./firebase";

// The student's past lessons, read the way HistoryModel.fetchRecentLessons does:
// `users/{uid}.questions` lists every lesson the backend settled for them
// (endLesson adds it), and each `questions/{qid}` document carries the rest.

/** One message of a finished lesson, as the backend archives the chat onto
 *  the question document when it settles (HistoryModel.lessonMessages). */
export interface LessonMessage {
  id: string;
  /** The text, or the address of an image, audio or video message. */
  text: string;
  senderRole: string;
  senderUid: string;
  /** "text", "image", "audio", "video" or "farewell". */
  kind: string;
  createdAt: number;
}

export interface PastLesson {
  questionId: string;
  title: string;
  questionText: string;
  topic: string;
  teacherName: string;
  /** When the lesson was accepted, epoch ms. */
  at: number;
  durationSeconds: number;
  /** What it cost, in minor units; null when billing has not said. */
  costCents: number | null;
  currency: string;
  conversationType: string;
  rating: number;
  photoUrls: string[];
  messages: LessonMessage[];
}

const millis = (v: unknown): number => {
  if (!v) return 0;
  if (typeof v === "number") return v;
  if (typeof v === "string") return Date.parse(v) || 0;
  if (typeof (v as { toMillis?: () => number }).toMillis === "function") return (v as { toMillis: () => number }).toMillis();
  return 0;
};

const firstString = (d: Record<string, unknown>, keys: string[]) => {
  for (const k of keys) {
    const v = d[k];
    if (typeof v === "string" && v.trim()) return v.trim();
  }
  return "";
};

/** The archived chat, stored as a list or as a map of push ids. */
export function lessonMessages(value: unknown): LessonMessage[] {
  const rows: [string, unknown][] = Array.isArray(value)
    ? value.map((v, i) => [String(i), v])
    : value && typeof value === "object"
      ? Object.entries(value as Record<string, unknown>)
      : [];
  return rows
    .map(([key, v]) => {
      const d = (v ?? {}) as Record<string, unknown>;
      const text = firstString(d, ["text", "message", "imageUrl", "photoUrl", "url"]);
      if (!text) return null;
      return {
        id: firstString(d, ["id", "messageId"]) || key,
        text,
        senderRole: firstString(d, ["senderRole", "role"]) || "student",
        senderUid: firstString(d, ["senderUid", "senderId", "uid"]),
        kind: firstString(d, ["kind", "type"]) || "text",
        createdAt: millis(d.createdAt),
      } satisfies LessonMessage;
    })
    .filter((m): m is LessonMessage => m !== null)
    .sort((a, b) => a.createdAt - b.createdAt);
}

/** A lesson's archived chat and medium, for a lesson listed without them
 *  (the teacher's, which come from the earnings summary). */
export async function fetchLessonArchive(questionId: string): Promise<{ messages: LessonMessage[]; conversationType: string }> {
  const data = (await getDoc(doc(firestore, "questions", questionId))).data() ?? {};
  return { messages: lessonMessages(data.messages), conversationType: String(data.conversationType ?? "") };
}

export type ReportReason = "inappropriate" | "harassment" | "sexual" | "off_platform" | "not_teaching" | "other";
export const REPORT_REASONS: ReportReason[] = ["inappropriate", "harassment", "sexual", "off_platform", "not_teaching", "other"];

/** Reports the lesson's teacher (and blocks them when `block`); the backend
 *  works out who the teacher is, saves the report and emails support. */
export async function reportTeacher(questionId: string, reason: ReportReason, details: string, block: boolean): Promise<void> {
  await httpsCallable(functions, "reportTeacher")({ questionId, reason, details: details.trim(), block });
}

/** Blocks the lesson's teacher: they are never sent this student's questions again. */
export async function blockTeacher(questionId: string): Promise<void> {
  await httpsCallable(functions, "blockTeacher")({ questionId });
}

const firstLine = (text: string) => text.split("\n").map((l) => l.trim()).find(Boolean) ?? "";

function toLesson(questionId: string, d: Record<string, unknown>): PastLesson {
  const questionText = String(d.text ?? d.questionText ?? "");
  const photoUrls = Array.isArray(d.photoUrls) ? d.photoUrls.map(String) : [];
  const durationSeconds = Math.max(0, Number(d.lessonSeconds ?? d.durationSeconds ?? 0) || 0);
  // `cost` is what billing writes (major units), and a stored 0 is the answer.
  const cost = d.cost === undefined || d.cost === null ? null : Number(d.cost);
  return {
    questionId,
    title: firstLine(questionText),
    questionText,
    topic: String(d.topic ?? ""),
    teacherName: String(d.teacherName ?? ""),
    at: millis(d.acceptedAt) || millis(d.startedAt) || millis(d.createdAt),
    durationSeconds,
    costCents: cost === null || Number.isNaN(cost) ? null : Math.round(cost * 100),
    currency: String(d.currency ?? d.currencyCode ?? "ILS").toUpperCase(),
    conversationType: String(d.conversationType ?? "text"),
    rating: Math.min(5, Math.max(0, Number(d.studentRating ?? 0) || 0)),
    photoUrls,
    messages: lessonMessages(d.messages),
  };
}

export async function fetchLessons(uid: string): Promise<PastLesson[]> {
  const user = await getDoc(doc(firestore, "users", uid));
  const ids = Array.isArray(user.data()?.questions) ? (user.data()!.questions as unknown[]).map(String) : [];
  const docs = await Promise.all(
    ids.map((id) =>
      getDoc(doc(firestore, "questions", id)).catch((e) => {
        console.error("[history] lesson read failed", id, e);
        return null;
      }),
    ),
  );
  return docs
    .filter((s) => s?.exists())
    .map((s) => toLesson(s!.id, s!.data()!))
    .sort((a, b) => b.at - a.at);
}

/** Minutes a lesson was billed: rounded to the nearest minute, as billing does. */
export const billedMinutes = (seconds: number) => Math.round(seconds / 60);
