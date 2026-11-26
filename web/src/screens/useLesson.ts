import { useCallback, useEffect, useRef, useState } from "react";
import type { Room, RemoteTrack } from "livekit-client";
import { auth } from "../services/firebase";
import {
  endLesson,
  fetchMediaCredentials,
  keepPresence,
  markLeft,
  rateTeacher,
  sendMessage,
  startLesson,
  watchMessages,
  watchQuestion,
  watchTeacherGone,
  type ChatMessage,
  type LiveQuestion,
} from "../services/lesson";
import { connectMedia, localCameraTrack, setMicrophone } from "../services/media";

export type LessonPhase = "connecting" | "waitingForTeacher" | "live" | "ending" | "rating" | "done";

export interface LessonInput {
  questionId: string;
  conversationType: string;
  liveKitToken?: string;
}

const READY_ATTEMPTS = 3;

/** The lesson's view model: joins the lesson the way ChatSessionService does
 *  (join → connect → ready → started), keeps presence, runs chat and media,
 *  and settles and rates the lesson at the end. */
export function useLesson(input: LessonInput, onFinished: () => void) {
  const { questionId } = input;
  const uid = auth.currentUser?.uid ?? "";
  const hasMedia = input.conversationType === "audio" || input.conversationType === "video";

  const [phase, setPhase] = useState<LessonPhase>("connecting");
  const [question, setQuestion] = useState<LiveQuestion | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [mediaError, setMediaError] = useState(false);
  const [cameraFailed, setCameraFailed] = useState(false);
  const [micOn, setMicOn] = useState(true);
  const [remoteTracks, setRemoteTracks] = useState<RemoteTrack[]>([]);
  const [room, setRoom] = useState<Room | null>(null);
  const [lessonSeconds, setLessonSeconds] = useState<number | null>(null);
  const [rating, setRating] = useState(0);
  const [comment, setComment] = useState("");
  const [ratingBusy, setRatingBusy] = useState(false);

  const roomRef = useRef<Room | null>(null);
  const stopPresence = useRef<(() => Promise<void>) | null>(null);
  const ending = useRef(false);
  const started = useRef(false);

  // Settles the lesson once, whichever way it ends.
  const finish = useCallback(
    async (stampLeave: boolean) => {
      if (ending.current) return;
      ending.current = true;
      setPhase("ending");
      if (stampLeave && started.current) {
        await markLeft(questionId).catch((e) => console.error("[lesson] markLeft failed", e));
      }
      try {
        const result = await endLesson(questionId);
        if (typeof result.lessonSeconds === "number") setLessonSeconds(result.lessonSeconds);
      } catch (e) {
        console.error("[lesson] endLesson failed", e);
      }
      await roomRef.current?.disconnect();
      roomRef.current = null;
      setRoom(null);
      await stopPresence.current?.().catch((e) => console.error("[lesson] stopPresence failed", e));
      stopPresence.current = null;
      // A lesson that never started has nothing to rate.
      setPhase(started.current ? "rating" : "done");
    },
    [questionId],
  );

  // Join, connect, report ready.
  useEffect(() => {
    let cancelled = false;
    const unsubs = [
      watchQuestion(questionId, (q) => {
        // The backend removes the live row as it settles the lesson; the
        // teacher's name and id are still needed for the rating after that.
        if (q) setQuestion(q);
        if (q && q.startedAt > 0 && !started.current) {
          started.current = true;
          setPhase((p) => (p === "connecting" || p === "waitingForTeacher" ? "live" : p));
        }
        if (!q || q.isOver) void finish(false);
      }),
      watchMessages(questionId, (m) => setMessages((list) => (list.some((x) => x.id === m.id) ? list : [...list, m]))),
      watchTeacherGone(questionId, () => void finish(false)),
    ];

    (async () => {
      try {
        await startLesson(questionId, false);
      } catch (e) {
        console.error("[lesson] startLesson join failed", e);
      }
      if (cancelled) return;
      // Kept from the join on, so a student who closes the tab while the two
      // sides connect is noticed in seconds.
      stopPresence.current = keepPresence(questionId);

      if (hasMedia) {
        try {
          let token = input.liveKitToken;
          if (!token) token = (await fetchMediaCredentials(questionId))?.token;
          if (!token) throw new Error("no LiveKit token");
          const media = await connectMedia(token, input.conversationType === "video", {
            onRemoteTrack: (t) => setRemoteTracks((list) => (list.includes(t) ? list : [...list, t])),
            onRemoteTrackGone: (t) => setRemoteTracks((list) => list.filter((x) => x !== t)),
            onDisconnected: () => setRemoteTracks([]),
          });
          if (cancelled) return void media.room.disconnect();
          roomRef.current = media.room;
          setRoom(media.room);
          setCameraFailed(media.cameraFailed);
        } catch (e) {
          // The lesson carries on by chat rather than ending in silence.
          console.error("[lesson] media connect failed", e);
          setMediaError(true);
        }
      }
      if (cancelled) return;

      for (let attempt = 1; attempt <= READY_ATTEMPTS && !ending.current; attempt++) {
        try {
          const { started: nowStarted } = await startLesson(questionId, true);
          if (nowStarted) {
            started.current = true;
            setPhase("live");
          } else {
            setPhase((p) => (p === "connecting" ? "waitingForTeacher" : p));
          }
          break;
        } catch (e) {
          console.error(`[lesson] ready report failed attempt=${attempt}`, e);
          await new Promise((r) => setTimeout(r, attempt * 2000));
        }
      }
    })();

    return () => {
      cancelled = true;
      unsubs.forEach((u) => u());
      void roomRef.current?.disconnect();
    };
    // Runs once per lesson.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [questionId]);

  const send = useCallback(async () => {
    const text = draft.trim();
    if (!text || !uid) return;
    setDraft("");
    try {
      await sendMessage(questionId, uid, text);
    } catch (e) {
      console.error("[lesson] sendMessage failed", e);
      setDraft(text);
    }
  }, [draft, uid, questionId]);

  const toggleMic = useCallback(async () => {
    if (!room) return;
    await setMicrophone(room, !micOn);
    setMicOn(!micOn);
  }, [room, micOn]);

  const submitRating = useCallback(async () => {
    if (!rating || !question?.teacherId) return;
    setRatingBusy(true);
    try {
      await rateTeacher(questionId, question.teacherId, rating, comment);
    } catch (e) {
      console.error("[lesson] rateTeacher failed", e);
    }
    setRatingBusy(false);
    onFinished();
  }, [rating, comment, question, questionId, onFinished]);

  return {
    uid,
    phase,
    question,
    messages,
    draft,
    setDraft,
    send,
    hasMedia,
    mediaError,
    cameraFailed,
    micOn,
    toggleMic,
    remoteTracks,
    localCamera: room ? localCameraTrack(room) : null,
    leave: () => finish(true),
    lessonSeconds,
    rating,
    setRating,
    comment,
    setComment,
    ratingBusy,
    submitRating,
    skipRating: onFinished,
  };
}
