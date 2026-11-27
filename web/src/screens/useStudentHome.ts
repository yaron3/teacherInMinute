import { useCallback, useEffect, useRef, useState } from "react";
import { useStrings } from "../i18n";
import {
  cancelQuestion,
  createQuestion,
  describeAskFailure,
  watchQuestionStatus,
  type ConversationType,
  type Topic,
} from "../services/questions";

export type SearchState =
  | { kind: "idle" }
  | { kind: "sending" }
  | { kind: "searching"; questionId: string }
  | { kind: "matched"; questionId: string; conversationType: ConversationType; liveKitToken?: string; questionText: string }
  | { kind: "noMatch" }
  | { kind: "cancelled" }
  | { kind: "error"; message: string };

const DRAFT_KEY = "studentHome.draft";
function readDraft(): { topic?: Topic; text?: string; conversationType?: ConversationType } {
  try {
    return JSON.parse(sessionStorage.getItem(DRAFT_KEY) ?? "{}");
  } catch {
    return {};
  }
}

/** The student home's view model: owns the ask → search → match flow, so the
 *  screen only renders state and forwards taps. */
export function useStudentHome() {
  const { t } = useStrings();
  // The question being written outlives the screen (QuestionDraftStore): an
  // anonymous student who creates an account to send it comes back to it
  // after the profile step.
  const draft = readDraft();
  const [topic, setTopic] = useState<Topic>(draft.topic ?? "algebra");
  const [text, setText] = useState(draft.text ?? "");
  const [conversationType, setConversationType] = useState<ConversationType>(draft.conversationType ?? "text");
  useEffect(() => {
    sessionStorage.setItem(DRAFT_KEY, JSON.stringify({ topic, text, conversationType }));
  }, [topic, text, conversationType]);
  const [search, setSearch] = useState<SearchState>({ kind: "idle" });
  const stopListening = useRef<(() => void) | null>(null);

  const stop = () => {
    stopListening.current?.();
    stopListening.current = null;
  };
  useEffect(() => stop, []);

  const canAsk = text.trim().length >= 10 && (search.kind === "idle" || search.kind === "error");

  const ask = useCallback(async () => {
    if (!canAsk) return;
    setSearch({ kind: "sending" });
    try {
      const asked = text.trim();
      const { questionId, liveKitToken } = await createQuestion(topic, asked, conversationType);
      setSearch({ kind: "searching", questionId });
      stop();
      stopListening.current = watchQuestionStatus(questionId, (status) => {
        if (status === "accepted" || status === "in_progress") {
          setSearch({ kind: "matched", questionId, conversationType, liveKitToken, questionText: asked });
          stop();
        } else if (status === "unanswered" || status === null) {
          setSearch({ kind: "noMatch" });
          stop();
        } else if (status === "cancelled") {
          setSearch({ kind: "cancelled" });
          stop();
        }
      });
    } catch (error) {
      console.error("[studentHome] createQuestion failed", error);
      const failure = describeAskFailure(error);
      const message =
        failure.kind === "noMinutes" ? t.noMinutes
        : failure.kind === "rateLimited" ? t.rateLimited(failure.retryAfterSeconds)
        : failure.kind === "tooLong" ? t.tooLong(failure.limit)
        : t.genericError;
      setSearch({ kind: "error", message });
    }
  }, [canAsk, topic, text, conversationType, t]);

  const cancel = useCallback(async () => {
    if (search.kind !== "searching") return;
    stop();
    try {
      await cancelQuestion(search.questionId);
    } catch (error) {
      console.error("[studentHome] cancelQuestion failed", error);
    }
    setSearch({ kind: "idle" });
  }, [search]);

  const reset = useCallback(() => {
    stop();
    setSearch({ kind: "idle" });
  }, []);

  // Back to a fresh ask once the lesson is over.
  const finishLesson = useCallback(() => {
    setText("");
    reset();
  }, [reset]);

  return { topic, setTopic, text, setText, conversationType, setConversationType, search, canAsk, ask, cancel, reset, finishLesson };
}
