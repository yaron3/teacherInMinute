import { useCallback, useEffect, useRef, useState } from "react";
import type { Room, RemoteTrack } from "livekit-client";
import { auth } from "../services/firebase";
import {
  answerBoardPermission,
  clearBoard,
  endLesson,
  eraseStrokes,
  fetchMediaCredentials,
  keepPresence,
  markLeft,
  rateTeacher,
  requestBoardPermission,
  sendMessage,
  sendStroke,
  setConversationType,
  setMediaPending,
  setMediaState,
  startLesson,
  updateViewport,
  watchBoard,
  watchBoardPermission,
  watchMessages,
  watchQuestion,
  watchPeerGone,
  watchPeerMedia,
  watchPeerViewport,
  peerOf,
  BOARD_SIZE,
  type BoardPermission,
  type BoardPoint,
  type BoardStroke,
  type BoardViewport,
  type ChatMessage,
  type LiveQuestion,
  type PeerMedia,
  type Role,
} from "../services/lesson";
import { connectMedia, localCameraTrack, probeDevices, setCamera, setMicrophone } from "../services/media";

export type LessonPhase = "connecting" | "waitingForTeacher" | "live" | "ending" | "rating" | "done";
export type Medium = "text" | "audio" | "video";

export interface LessonInput {
  questionId: string;
  conversationType: string;
  liveKitToken?: string;
  questionText?: string;
  /** Which side this is; a student unless said. */
  role?: Role;
}

/** Why the lesson's media is not what was picked, as the screen explains it. */
export type MediaNotice = "connectFailed" | "cameraFailed" | "permissionDenied" | null;

/** Where the student's credit stands (MinutesHoldState on the apps). */
export type MinutesState = "none" | "warning" | "held";

const READY_ATTEMPTS = 3;
/** board_draw_permission_seconds' default on the apps. */
const DRAW_WINDOW_MS = 60_000;
const MINUTES_WARNING_SECONDS = 60;

const rank = (m: string) => (m === "video" ? 2 : m === "audio" ? 1 : 0);
const asMedium = (m: string): Medium => (m === "video" || m === "audio" ? m : "text");

/** The lesson's view model: joins the lesson the way ChatSessionService does
 *  (join → connect → ready → started), keeps presence, runs chat, media and
 *  the board, follows the shared medium, and settles and rates at the end. */
export function useLesson(input: LessonInput, onFinished: () => void) {
  const { questionId } = input;
  const role: Role = input.role ?? "student";
  const peer = peerOf(role);
  const isTeacher = role === "teacher";
  const uid = auth.currentUser?.uid ?? "";

  const [phase, setPhase] = useState<LessonPhase>("connecting");
  const [question, setQuestion] = useState<LiveQuestion | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [draft, setDraft] = useState("");
  const [lessonSeconds, setLessonSeconds] = useState<number | null>(null);
  const [now, setNow] = useState(() => Date.now());

  // Media.
  const [medium, setMediumState] = useState<Medium>(asMedium(input.conversationType));
  const [switching, setSwitching] = useState(false);
  const [mediaNotice, setMediaNotice] = useState<MediaNotice>(null);
  const [peerOffer, setPeerOffer] = useState<Medium | null>(null);
  const [peerMedia, setPeerMedia] = useState<PeerMedia>({ pending: false, micMuted: false, cameraOff: false });
  const [micOn, setMicOn] = useState(true);
  const [cameraOn, setCameraOn] = useState(true);
  const [remoteTracks, setRemoteTracks] = useState<RemoteTrack[]>([]);
  const [room, setRoom] = useState<Room | null>(null);
  const [cameraVersion, setCameraVersion] = useState(0);

  // Board.
  const [strokes, setStrokes] = useState<BoardStroke[]>([]);
  const [teacherViewport, setTeacherViewport] = useState<BoardViewport | null>(null);
  const [drawUntil, setDrawUntil] = useState<number | null>(null);
  const [drawRequestPending, setDrawRequestPending] = useState(false);
  const [drawDeclined, setDrawDeclined] = useState(false);
  /** Teacher only: a student's ask to draw, waiting for an answer. */
  const [drawRequest, setDrawRequest] = useState<string | null>(null);

  // Rating.
  const [rating, setRating] = useState(0);
  const [comment, setComment] = useState("");
  const [ratingBusy, setRatingBusy] = useState(false);

  const roomRef = useRef<Room | null>(null);
  const mediumRef = useRef<Medium>(medium);
  const lastSeenShared = useRef("");
  const stopPresence = useRef<(() => Promise<void>) | null>(null);
  const ending = useRef(false);
  const started = useRef(false);
  const ownRequestId = useRef<string | null>(null);
  const lastGrantedId = useRef<string | null>(null);
  const permissionRead = useRef(false);
  const answeredRequests = useRef(new Set<string>());

  const setMedium = (m: Medium) => {
    mediumRef.current = m;
    setMediumState(m);
  };

  const attachRoom = (r: Room | null) => {
    roomRef.current = r;
    setRoom(r);
    setCameraVersion((v) => v + 1);
  };

  const mediaHandlers = {
    onRemoteTrack: (t: RemoteTrack) => setRemoteTracks((list) => (list.includes(t) ? list : [...list, t])),
    onRemoteTrackGone: (t: RemoteTrack) => setRemoteTracks((list) => list.filter((x) => x !== t)),
    onDisconnected: () => setRemoteTracks([]),
  };

  const publishDevices = (mic: boolean, camera: boolean) =>
    setMediaState(questionId, role, !mic, !camera).catch((e) => console.error("[lesson] mediaState write failed", e));

  /** Moves this side's media to `target`: joins the room, turns the camera on
   *  or off, or leaves the room for a chat lesson (applyConversationType). */
  const applyMedium = useCallback(
    async (target: Medium): Promise<boolean> => {
      if (target === mediumRef.current && (target === "text" || roomRef.current)) return true;
      if (ending.current) return false;
      setSwitching(true);
      setMediaNotice(null);
      try {
        if (target === "text") {
          await roomRef.current?.disconnect();
          attachRoom(null);
          setRemoteTracks([]);
          setMedium("text");
          await setMediaPending(questionId, role, false).catch((e) => console.error("[lesson] mediaPending write failed", e));
          return true;
        }
        const withVideo = target === "video";
        if (roomRef.current) {
          await setCamera(roomRef.current, withVideo);
        } else {
          let token = input.liveKitToken;
          if (!token) token = (await fetchMediaCredentials(questionId))?.token;
          if (!token) throw new Error("no LiveKit token");
          const media = await connectMedia(token, withVideo, mediaHandlers);
          if (ending.current) {
            await media.room.disconnect();
            return false;
          }
          attachRoom(media.room);
          if (media.cameraFailed) setMediaNotice("cameraFailed");
        }
        setCameraVersion((v) => v + 1);
        setMedium(target);
        // Both toggles start on after a switch, as resetMediaToggles does; the
        // camera one only matters in video.
        setMicOn(true);
        setCameraOn(true);
        void publishDevices(true, true);
        await setMediaPending(questionId, role, false).catch((e) => console.error("[lesson] mediaPending write failed", e));
        return true;
      } catch (e) {
        // The lesson carries on by chat rather than ending in silence, and the
        // teacher is told this side is without audio.
        console.error("[lesson] media switch failed", e);
        await roomRef.current?.disconnect();
        attachRoom(null);
        setMedium("text");
        setMediaNotice("connectFailed");
        await setMediaPending(questionId, role, true).catch((err) => console.error("[lesson] mediaPending write failed", err));
        return false;
      } finally {
        setSwitching(false);
      }
    },
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [questionId],
  );

  // Settles the lesson once, whichever way it ends.
  const finish = useCallback(
    async (stampLeave: boolean) => {
      if (ending.current) return;
      ending.current = true;
      setPhase("ending");
      if (stampLeave && started.current) {
        await markLeft(questionId, role).catch((e) => console.error("[lesson] markLeft failed", e));
      }
      try {
        const result = await endLesson(questionId);
        if (typeof result.lessonSeconds === "number") setLessonSeconds(result.lessonSeconds);
      } catch (e) {
        console.error("[lesson] endLesson failed", e);
      }
      await roomRef.current?.disconnect();
      attachRoom(null);
      await stopPresence.current?.().catch((e) => console.error("[lesson] stopPresence failed", e));
      stopPresence.current = null;
      // A lesson that never started has nothing to rate; a teacher rates no one.
      setPhase(started.current && !isTeacher ? "rating" : "done");
    },
    [questionId],
  );

  /** The teacher changed the shared medium. Dropping media is followed at
   *  once; adding it waits for the student to agree (sharedConversationTypeChange). */
  const followShared = (shared: string) => {
    if (!["text", "audio", "video"].includes(shared)) return;
    if (!lastSeenShared.current) {
      lastSeenShared.current = shared;
      return;
    }
    if (shared === lastSeenShared.current || !started.current || ending.current) return;
    lastSeenShared.current = shared;
    if (rank(shared) > rank(mediumRef.current)) {
      setPeerOffer(asMedium(shared));
    } else {
      setPeerOffer(null);
      void applyMedium(asMedium(shared));
    }
  };

  const receivePermission = (p: BoardPermission | null) => {
    const first = !permissionRead.current;
    permissionRead.current = true;
    if (!p) return;
    if (isTeacher) {
      // A fresh ask waits for an answer; anything else settles one shown.
      if (p.status === "requested" && !answeredRequests.current.has(p.requestId)) setDrawRequest(p.requestId);
      else setDrawRequest((current) => (current === p.requestId ? null : current));
      return;
    }
    if (p.status === "granted") {
      // A grant standing when this side joined belongs to an earlier stretch
      // of the lesson, most likely long run out, so it is not restarted.
      if (first) {
        lastGrantedId.current = p.requestId;
      } else if (lastGrantedId.current !== p.requestId) {
        lastGrantedId.current = p.requestId;
        setDrawUntil(Date.now() + DRAW_WINDOW_MS);
      }
      if (p.requestId === ownRequestId.current) {
        ownRequestId.current = null;
        setDrawRequestPending(false);
      }
    } else if (p.status === "declined" && p.requestId === ownRequestId.current) {
      ownRequestId.current = null;
      setDrawRequestPending(false);
      setDrawDeclined(true);
    }
  };

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
        if (q) followShared(q.conversationType);
        if (!q || q.isOver) void finish(false);
      }),
      watchMessages(questionId, (m) => setMessages((list) => (list.some((x) => x.id === m.id) ? list : [...list, m]))),
      watchPeerGone(questionId, peer, () => void finish(false)),
      watchPeerMedia(questionId, peer, setPeerMedia),
      watchBoard(questionId, setStrokes),
      watchPeerViewport(questionId, peer, setTeacherViewport),
      watchBoardPermission(questionId, receivePermission),
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
      stopPresence.current = keepPresence(questionId, role);
      // On a big screen the whole board is in view, as on the iPad.
      void updateViewport(questionId, role, { x: 0, y: 0, width: BOARD_SIZE, height: BOARD_SIZE }).catch((e) =>
        console.error("[lesson] viewport write failed", e),
      );

      const asked = asMedium(input.conversationType);
      if (asked !== "text") {
        // applyMedium skips a medium it is already on; this one is not joined yet.
        mediumRef.current = "text";
        await applyMedium(asked);
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

  // One tick a second drives the session clock, the credit warning and the
  // draw window.
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);

  // ─── Chat ──────────────────────────────────────────────────────────────────

  const send = useCallback(async () => {
    const text = draft.trim();
    if (!text || !uid) return;
    setDraft("");
    try {
      await sendMessage(questionId, role, uid, text);
    } catch (e) {
      console.error("[lesson] sendMessage failed", e);
      setDraft(text);
    }
  }, [draft, uid, questionId]);

  // ─── Media ─────────────────────────────────────────────────────────────────

  /** The student picked a new medium: check the devices, tell the teacher,
   *  then switch (requestConversationType). */
  const chooseMedium = useCallback(
    async (target: Medium) => {
      if (target === mediumRef.current || switching || ending.current) return;
      if (target !== "text" && !(await probeDevices(target === "video"))) {
        setMediaNotice("permissionDenied");
        return;
      }
      setPeerOffer(null);
      const previous = lastSeenShared.current;
      lastSeenShared.current = target;
      try {
        await setConversationType(questionId, target);
      } catch (e) {
        console.error("[lesson] conversationType write failed", e);
        lastSeenShared.current = previous;
        setMediaNotice("connectFailed");
        return;
      }
      await applyMedium(target);
    },
    [questionId, switching, applyMedium],
  );

  const acceptPeerOffer = useCallback(async () => {
    const target = peerOffer;
    setPeerOffer(null);
    if (!target) return;
    if (!(await probeDevices(target === "video"))) {
      setMediaNotice("permissionDenied");
      if (rank(mediumRef.current) === 0) void setMediaPending(questionId, role, true);
      return;
    }
    await applyMedium(target);
  }, [peerOffer, questionId, applyMedium]);

  /** Stays on the current medium; without audio, the teacher is told to use
   *  the chat (declinePeerConversationType). */
  const declinePeerOffer = useCallback(() => {
    setPeerOffer(null);
    if (rank(mediumRef.current) === 0) {
      void setMediaPending(questionId, role, true).catch((e) => console.error("[lesson] mediaPending write failed", e));
    }
  }, [questionId]);

  const toggleMic = useCallback(async () => {
    if (!room) return;
    const next = !micOn;
    await setMicrophone(room, next);
    setMicOn(next);
    void publishDevices(next, cameraOn);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [room, micOn, cameraOn]);

  const toggleCamera = useCallback(async () => {
    if (!room || mediumRef.current !== "video") return;
    const next = !cameraOn;
    await setCamera(room, next);
    setCameraOn(next);
    setCameraVersion((v) => v + 1);
    void publishDevices(micOn, next);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [room, micOn, cameraOn]);

  // ─── Board ─────────────────────────────────────────────────────────────────

  // The teacher always may; the student with leave (canDrawOnBoard).
  const canDraw = isTeacher || (drawUntil !== null && drawUntil > now);

  const drawStroke = useCallback(
    async (points: BoardPoint[]) => {
      if (!points.length || !uid || ending.current) return;
      // Each stroke restarts the window, as long as one was granted.
      setDrawUntil((until) => (until ? Date.now() + DRAW_WINDOW_MS : until));
      const local: BoardStroke = { id: `local-${Date.now()}`, points, createdAt: Date.now(), senderUid: uid };
      setStrokes((list) => [...list, local]);
      try {
        await sendStroke(questionId, uid, points);
      } catch (e) {
        console.error("[lesson] stroke send failed", e);
        setStrokes((list) => list.filter((s) => s.id !== local.id));
      }
    },
    [questionId, uid],
  );

  const erase = useCallback(
    async (ids: string[]) => {
      // A teacher rubs out anything; a student only their own (canErase).
      const own = ids.filter((id) => strokes.some((s) => s.id === id && (isTeacher || s.senderUid === uid)));
      if (!own.length) return;
      setStrokes((list) => list.filter((s) => !own.includes(s.id)));
      await eraseStrokes(questionId, own).catch((e) => console.error("[lesson] erase failed", e));
    },
    [questionId, strokes, uid],
  );

  const clear = useCallback(async () => {
    if (!isTeacher || ending.current) return;
    setStrokes([]);
    await clearBoard(questionId).catch((e) => console.error("[lesson] clear failed", e));
  }, [isTeacher, questionId]);

  const answerDrawRequest = useCallback(
    async (approve: boolean) => {
      const id = drawRequest;
      if (!id) return;
      setDrawRequest(null);
      answeredRequests.current.add(id);
      await answerBoardPermission(questionId, id, approve).catch((e) => console.error("[lesson] draw answer failed", e));
    },
    [drawRequest, questionId],
  );

  const askToDraw = useCallback(async () => {
    if (drawRequestPending || ending.current) return;
    const id = crypto.randomUUID();
    ownRequestId.current = id;
    setDrawRequestPending(true);
    setDrawDeclined(false);
    try {
      await requestBoardPermission(questionId, id);
    } catch (e) {
      console.error("[lesson] draw request failed", e);
      if (ownRequestId.current === id) {
        ownRequestId.current = null;
        setDrawRequestPending(false);
      }
    }
  }, [drawRequestPending, questionId]);

  // ─── Clock and credit ──────────────────────────────────────────────────────

  const startedAt = question?.startedAt ?? 0;
  const elapsedSeconds =
    lessonSeconds !== null ? lessonSeconds : startedAt > 0 ? Math.max(0, Math.floor((now - startedAt) / 1000)) : 0;
  const deadline = question?.minutesDeadlineAt ?? 0;
  const secondsLeft = deadline > 0 ? Math.floor((deadline - now) / 1000) : null;
  const minutesState: MinutesState =
    isTeacher || secondsLeft === null || phase !== "live" ? "none" : secondsLeft <= 0 ? "held" : secondsLeft <= MINUTES_WARNING_SECONDS ? "warning" : "none";

  // ─── Rating ────────────────────────────────────────────────────────────────

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

  // Reading cameraVersion keeps the self view current after camera changes.
  void cameraVersion;
  const localCamera = room && medium === "video" && cameraOn ? localCameraTrack(room) : null;

  return {
    uid,
    role,
    isTeacher,
    /** The other side's name, as the question carries it. */
    peerName: (isTeacher ? question?.studentName : question?.teacherName) ?? "",
    phase,
    question,
    questionText: question?.questionText || input.questionText || "",
    messages,
    draft,
    setDraft,
    send,
    // Media
    medium,
    switching,
    chooseMedium,
    mediaNotice,
    dismissMediaNotice: () => setMediaNotice(null),
    peerOffer,
    acceptPeerOffer,
    declinePeerOffer,
    peerMedia,
    micOn,
    cameraOn,
    toggleMic,
    toggleCamera,
    remoteTracks,
    localCamera,
    // Board
    strokes,
    teacherViewport,
    canDraw,
    drawSecondsLeft: canDraw && drawUntil ? Math.ceil((drawUntil - now) / 1000) : 0,
    drawRequestPending,
    drawDeclined,
    dismissDrawDeclined: () => setDrawDeclined(false),
    askToDraw,
    drawRequest,
    answerDrawRequest,
    clear,
    drawStroke,
    erase,
    // Clock
    elapsedSeconds,
    secondsLeft,
    minutesState,
    // Ending
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

export type LessonModel = ReturnType<typeof useLesson>;
