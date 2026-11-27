import { onValue, ref } from "firebase/database";
import { FirebaseError } from "firebase/app";
import { httpsCallable } from "firebase/functions";
import { database, functions } from "./firebase";

/** backend/Firebase/functions/src/types.ts — QUESTION_TOPICS. */
export const TOPICS = ["algebra", "geometry", "trigonometry", "calculus", "statistics", "arithmetic"] as const;
export type Topic = (typeof TOPICS)[number];

export type ConversationType = "text" | "audio" | "video";

/** types.ts — QuestionStatus. */
export type QuestionStatus = "searching" | "accepted" | "in_progress" | "completed" | "cancelled" | "unanswered";

export interface CreatedQuestion {
  questionId: string;
  searchTimeoutSeconds?: number;
  liveKitRoom?: string;
  liveKitToken?: string;
}

/** Why the backend refused a question, as the mobile apps tell them apart
 *  (StudentHomeViewModel.askTeacher). */
export type AskFailure =
  | { kind: "noMinutes" }
  | { kind: "rateLimited"; retryAfterSeconds: number }
  | { kind: "tooLong"; limit: number }
  | { kind: "invalid"; message: string }
  | { kind: "other"; message: string };

export async function createQuestion(topic: Topic, text: string, conversationType: ConversationType): Promise<CreatedQuestion> {
  const call = httpsCallable<object, CreatedQuestion>(functions, "createQuestion");
  const result = await call({ topic, text, photoUrls: [], conversationType });
  return result.data;
}

export async function cancelQuestion(questionId: string): Promise<void> {
  await httpsCallable(functions, "cancelQuestion")({ questionId });
}

export function describeAskFailure(error: unknown): AskFailure {
  if (error instanceof FirebaseError) {
    const details = (error as FirebaseError & { details?: Record<string, unknown> }).details ?? {};
    const reason = details.reason;
    if (reason === "rate_limited") return { kind: "rateLimited", retryAfterSeconds: Number(details.retryAfterSeconds ?? 60) };
    if (reason === "question_too_long") return { kind: "tooLong", limit: Number(details.limit ?? 0) };
    if (error.code === "functions/resource-exhausted") return { kind: "noMinutes" };
    if (error.code === "functions/invalid-argument") return { kind: "invalid", message: error.message };
    return { kind: "other", message: error.message };
  }
  return { kind: "other", message: String(error) };
}

/** Follows `questions/{qid}` in RTDB, where the backend pushes every status
 *  change (QuestionStatusStore on mobile). `null` means the row is gone. */
export function watchQuestionStatus(questionId: string, onChange: (status: QuestionStatus | null) => void): () => void {
  return onValue(
    ref(database, `questions/${questionId}`),
    (snap) => {
      const status = snap.child("status").val();
      if (typeof status === "string" && status) onChange(status as QuestionStatus);
      else if (!snap.exists()) onChange(null);
    },
    (error) => console.error("[questions] status listener cancelled", error),
  );
}
