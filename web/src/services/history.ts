import { doc, getDoc } from "firebase/firestore";
import { firestore } from "./firebase";

// The student's past lessons, read the way HistoryModel.fetchRecentLessons does:
// `users/{uid}.questions` lists every lesson the backend settled for them
// (endLesson adds it), and each `questions/{qid}` document carries the rest.

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
}

const millis = (v: unknown): number => {
  if (!v) return 0;
  if (typeof v === "number") return v;
  if (typeof v === "string") return Date.parse(v) || 0;
  if (typeof (v as { toMillis?: () => number }).toMillis === "function") return (v as { toMillis: () => number }).toMillis();
  return 0;
};

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
