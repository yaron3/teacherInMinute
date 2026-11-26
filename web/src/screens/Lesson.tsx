import { useEffect, useRef, useState } from "react";
import type { LocalTrack, RemoteTrack } from "livekit-client";
import { useStrings } from "../i18n";
import { Board, TOOLS, type Tool } from "./Board";
import { useLesson, type LessonInput, type LessonModel, type Medium } from "./useLesson";

/** Puts a LiveKit track on the page (video element, or a hidden audio one). */
function TrackView({ track, muted, className }: { track: RemoteTrack | LocalTrack; muted?: boolean; className?: string }) {
  const el = useRef<HTMLVideoElement & HTMLAudioElement>(null);
  useEffect(() => {
    const node = el.current;
    if (!node) return;
    track.attach(node);
    return () => {
      track.detach(node);
    };
  }, [track]);
  return track.kind === "video" ? (
    <video ref={el} className={className} autoPlay playsInline muted={muted} />
  ) : (
    <audio ref={el} autoPlay />
  );
}

const TOOL_ICONS: Record<Tool, string> = { pen: "✎", line: "╱", triangle: "△", circle: "○", rectangle: "□", eraser: "⌫" };

function clock(seconds: number) {
  const s = Math.max(0, seconds);
  return `${String(Math.floor(s / 60)).padStart(2, "0")}:${String(s % 60).padStart(2, "0")}`;
}

function initials(name: string) {
  return name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase() || "?";
}

/** A small modal over the lesson. */
function Dialog({ title, body, children }: { title: string; body?: string; children: React.ReactNode }) {
  return (
    <div className="scrim" role="dialog" aria-modal="true" aria-label={title}>
      <div className="dialog">
        <h3>{title}</h3>
        {body && <p className="muted">{body}</p>}
        <div className="dialog-actions">{children}</div>
      </div>
    </div>
  );
}

export function Lesson({ input, onFinished }: { input: LessonInput; onFinished: () => void }) {
  const vm = useLesson(input, onFinished);
  if (vm.phase === "rating") return <RatingCard vm={vm} />;
  if (vm.phase === "done" || vm.phase === "ending") return <EndedCard vm={vm} onFinished={onFinished} />;
  return <LiveLesson vm={vm} />;
}

/** Wide enough to show the chat beside the board. */
const SPLIT_QUERY = "(min-width: 900px)";
const CHAT_WIDTH_KEY = "lesson.chatWidth";
const CHAT_MIN = 280;
const BOARD_MIN = 360;
const CHAT_DEFAULT = 400;

function useMediaQuery(query: string) {
  const [matches, setMatches] = useState(() => window.matchMedia(query).matches);
  useEffect(() => {
    const list = window.matchMedia(query);
    const onChange = () => setMatches(list.matches);
    list.addEventListener("change", onChange);
    return () => list.removeEventListener("change", onChange);
  }, [query]);
  return matches;
}

/** The chat column's width beside the board, dragged by its handle and kept
 *  between lessons. */
function useChatWidth(body: React.RefObject<HTMLElement | null>) {
  const [width, setWidth] = useState(() => Number(localStorage.getItem(CHAT_WIDTH_KEY)) || CHAT_DEFAULT);
  const clamp = (w: number) => {
    const total = body.current?.clientWidth ?? window.innerWidth;
    return Math.round(Math.max(CHAT_MIN, Math.min(total - BOARD_MIN, w)));
  };
  const set = (w: number | ((current: number) => number)) => {
    setWidth((current) => {
      const next = clamp(typeof w === "function" ? w(current) : w);
      localStorage.setItem(CHAT_WIDTH_KEY, String(next));
      return next;
    });
  };
  // Keep it inside the window when the window shrinks.
  useEffect(() => {
    const onResize = () => setWidth((w) => clamp(w));
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return [width, set] as const;
}

function LiveLesson({ vm }: { vm: LessonModel }) {
  const { t } = useStrings();
  const [tab, setTab] = useState<"chat" | "board">("chat");
  const [tool, setTool] = useState<Tool>("pen");
  const [mediaMenu, setMediaMenu] = useState(false);
  const [askDraw, setAskDraw] = useState(false);
  const [confirmClear, setConfirmClear] = useState(false);
  const bottom = useRef<HTMLDivElement>(null);
  const body = useRef<HTMLElement>(null);
  // On a big screen the chat sits beside the board; on a small one they are tabs.
  const split = useMediaQuery(SPLIT_QUERY);
  const [chatWidth, setChatWidth] = useChatWidth(body);
  const [dragging, setDragging] = useState(false);
  const rtl = document.documentElement.dir === "rtl";
  const showChat = split || tab === "chat";
  const showBoard = split || tab === "board";

  /** The chat's width for a pointer at `clientX`: the chat is on the start
   *  side, which is the right in Hebrew. */
  const widthAt = (clientX: number) => {
    const r = body.current!.getBoundingClientRect();
    return rtl ? r.right - clientX : clientX - r.left;
  };
  const mediumName = (m: Medium) => (m === "video" ? t.video : m === "audio" ? t.audio : t.text);
  // The other side, named as the question carries them.
  const peerName = vm.peerName || (vm.isTeacher ? t.studentRole : t.yourTeacher);

  // Braces matter: newer Chromium returns a Promise from scrollIntoView, and an
  // effect that returns anything but a cleanup function takes the page down.
  useEffect(() => {
    if (showChat) bottom.current?.scrollIntoView({ block: "end" });
  }, [vm.messages.length, showChat]);

  // The cameras float over the board, as on the apps.
  useEffect(() => {
    if (vm.medium === "video") setTab("board");
  }, [vm.medium]);

  const remoteVideo = vm.remoteTracks.find((tr) => tr.kind === "video");
  const remoteAudio = vm.remoteTracks.filter((tr) => tr.kind === "audio");
  const status = vm.phase === "connecting" ? t.connecting : vm.phase === "waitingForTeacher" ? t.waitingForTeacher : null;
  const notice =
    vm.mediaNotice === "connectFailed" ? t.mediaFailed
    : vm.mediaNotice === "cameraFailed" ? t.cameraFailed
    : vm.mediaNotice === "permissionDenied" ? t.permissionDenied
    : null;

  return (
    <div className="session">
      <header className="session-top">
        {split ? (
          <strong className="session-title">{peerName}</strong>
        ) : (
        <div className="segmented" role="tablist">
          <button role="tab" aria-selected={tab === "chat"} className={tab === "chat" ? "on" : ""} onClick={() => setTab("chat")}>
            <span aria-hidden>💬</span> {t.chatTab}
          </button>
          <button role="tab" aria-selected={tab === "board"} className={tab === "board" ? "on" : ""} onClick={() => setTab("board")}>
            <span aria-hidden>▭</span> {t.boardTab}
          </button>
        </div>
        )}
        {status && <span className="session-status">{status}</span>}
        <button className="end-button" onClick={vm.leave} aria-label={t.endLesson} title={t.endLesson}>
          ✕
        </button>
      </header>

      {(notice || (vm.peerMedia.pending && vm.medium !== "text")) && (
        <div className="session-banner" role="status">
          <span>{notice ?? (vm.isTeacher ? t.studentOnChat : t.teacherOnChat)}</span>
          {notice && (
            <button className="link" onClick={vm.dismissMediaNotice}>
              {t.ok}
            </button>
          )}
        </div>
      )}
      {vm.minutesState !== "none" && (
        <div className={vm.minutesState === "held" ? "session-banner danger-banner" : "session-banner warn-banner"} role="alert">
          {vm.minutesState === "held" ? t.minutesHeld : t.minutesWarning(vm.secondsLeft ?? 0)}
          {/* A new tab, so the lesson stays open; minutes bought there extend it. */}
          <a className="banner-link" href="/#buy" target="_blank" rel="noreferrer">
            {t.buyMinutesLink}
          </a>
        </div>
      )}

      <main className={dragging ? "session-body dragging" : "session-body"} ref={body}>
        {showChat && (
          <div className={split ? "chat-pane side" : "chat-pane"} style={split ? { width: chatWidth } : undefined}>
            <div className="thread">
              {vm.questionText && (
                <div className="pinned">
                  <span className="pin" aria-hidden>📌</span>
                  <div>
                    <div className="pinned-label">{t.originalQuestion}</div>
                    <div dir="auto">{vm.questionText}</div>
                  </div>
                </div>
              )}
              {vm.messages.map((m) => {
                const mine = m.senderUid === vm.uid;
                return (
                  <div key={m.id} className={mine ? "row mine" : "row"}>
                    {!mine && <div className="avatar small">{initials(peerName)}</div>}
                    <div dir="auto" className={mine ? "bubble mine" : "bubble"}>
                      {m.text}
                      <span className="bubble-time">
                        <bdi>{new Date(m.createdAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</bdi>
                      </span>
                    </div>
                  </div>
                );
              })}
              <div ref={bottom} />
            </div>
            <form
              className="composer"
              onSubmit={(e) => {
                e.preventDefault();
                void vm.send();
              }}
            >
              <button className="send" type="submit" disabled={!vm.draft.trim()} aria-label={t.send}>
                ➤
              </button>
              <input dir="auto" value={vm.draft} onChange={(e) => vm.setDraft(e.target.value)} placeholder={t.messagePlaceholder} />
            </form>
          </div>
        )}
        {split && (
          <div
            className="splitter"
            role="separator"
            aria-orientation="vertical"
            aria-label={t.resizeChat}
            aria-valuenow={chatWidth}
            aria-valuemin={CHAT_MIN}
            tabIndex={0}
            title={t.resizeChat}
            onPointerDown={(e) => {
              e.currentTarget.setPointerCapture(e.pointerId);
              setDragging(true);
            }}
            onPointerMove={(e) => dragging && setChatWidth(widthAt(e.clientX))}
            onPointerUp={() => setDragging(false)}
            onPointerCancel={() => setDragging(false)}
            onDoubleClick={() => setChatWidth(CHAT_DEFAULT)}
            onKeyDown={(e) => {
              const step = e.shiftKey ? 80 : 20;
              const grow = rtl ? "ArrowLeft" : "ArrowRight";
              const shrink = rtl ? "ArrowRight" : "ArrowLeft";
              if (e.key === grow) setChatWidth((w) => w + step);
              else if (e.key === shrink) setChatWidth((w) => w - step);
              else return;
              e.preventDefault();
            }}
          >
            <span className="grip" />
          </div>
        )}
        {showBoard && (
          <div className="board-pane">
            <div className="toolbar">
              {TOOLS.map((tl) => (
                <button
                  key={tl}
                  className={tl === tool ? "tool on" : "tool"}
                  onClick={() => setTool(tl)}
                  aria-label={t.tools[tl]}
                  title={t.tools[tl]}
                >
                  {TOOL_ICONS[tl]}
                </button>
              ))}
              <span className="toolbar-gap" />
              {vm.isTeacher ? (
                <button className="tool" onClick={() => setConfirmClear(true)} aria-label={t.clearBoard} title={t.clearBoard}>
                  🗑
                </button>
              ) : vm.canDraw ? (
                <span className="draw-chip">{t.drawAllowed(vm.drawSecondsLeft)}</span>
              ) : (
                <button className="secondary small" onClick={vm.askToDraw} disabled={vm.drawRequestPending}>
                  {vm.drawRequestPending ? t.askToDrawPending : t.askToDraw}
                </button>
              )}
            </div>
            <Board
              strokes={vm.strokes}
              uid={vm.uid}
              tool={tool}
              teacherViewport={vm.teacherViewport}
              canDraw={vm.canDraw || tool === "eraser"}
              isTeacher={vm.isTeacher}
              onBlocked={() => !vm.drawRequestPending && setAskDraw(true)}
              onStroke={vm.drawStroke}
              onErase={vm.erase}
            />
          </div>
        )}

        {vm.medium === "video" && (
          <div className="video-float">
            {remoteVideo && !vm.peerMedia.cameraOff ? (
              <TrackView track={remoteVideo} className="remote" />
            ) : (
              <div className="remote placeholder">
                <div className="avatar">{initials(peerName)}</div>
                {vm.peerMedia.cameraOff && <small>{vm.isTeacher ? t.studentCameraOff : t.teacherCameraOff}</small>}
              </div>
            )}
            {vm.localCamera && <TrackView track={vm.localCamera} muted className="self" />}
          </div>
        )}
        {remoteAudio.map((tr) => (
          <TrackView key={tr.sid} track={tr} />
        ))}
      </main>

      <footer className="session-bar">
        <div className="media-control">
          <button
            className="media-button"
            onClick={() => setMediaMenu((v) => !v)}
            aria-haspopup="menu"
            aria-expanded={mediaMenu}
            aria-label={t.changeMedia}
            disabled={vm.switching}
          >
            ⋮
          </button>
          <span className="bar-label">{vm.switching ? t.switchingMedia : t.mediaLabel(mediumName(vm.medium))}</span>
          {mediaMenu && (
            <div className="media-menu" role="menu">
              {(["text", "audio", "video"] as Medium[]).map((m) => (
                <button
                  key={m}
                  role="menuitemradio"
                  aria-checked={vm.medium === m}
                  className={vm.medium === m ? "on" : ""}
                  onClick={() => {
                    setMediaMenu(false);
                    void vm.chooseMedium(m);
                  }}
                >
                  {mediumName(m)}
                </button>
              ))}
            </div>
          )}
        </div>

        {vm.medium !== "text" && (
          <>
            <button className={vm.micOn ? "round-toggle" : "round-toggle off"} onClick={vm.toggleMic} aria-label={vm.micOn ? t.mute : t.unmute} title={vm.micOn ? t.mute : t.unmute}>
              {vm.micOn ? "🎙" : "🔇"}
            </button>
            {vm.medium === "video" && (
              <button className={vm.cameraOn ? "round-toggle" : "round-toggle off"} onClick={vm.toggleCamera} aria-label={vm.cameraOn ? t.cameraOff : t.cameraOn} title={vm.cameraOn ? t.cameraOff : t.cameraOn}>
                {vm.cameraOn ? "📷" : "🚫"}
              </button>
            )}
          </>
        )}

        <div className="participant">
          <div className="avatar">
            {initials(peerName)}
            <span className={vm.phase === "live" ? "dot online" : "dot"} />
          </div>
          <strong>{peerName}</strong>
          <small>{vm.peerMedia.micMuted && vm.medium !== "text" ? t.micMuted : vm.isTeacher ? t.studentRole : t.teacherRole}</small>
        </div>
        <div className="participant">
          <div className="avatar">
            {initials(t.you)}
            <span className="dot online" />
          </div>
          <strong>{t.you}</strong>
          <small>{vm.isTeacher ? t.teacherRole : t.studentRole}</small>
        </div>

        <span className="bar-gap" />
        <div className="session-clock">
          <strong>{clock(vm.elapsedSeconds)}</strong>
          <small>{t.sessionTime}</small>
        </div>
      </footer>

      {vm.peerOffer && (
        <Dialog title={(vm.isTeacher ? t.peerOfferTitleStudent : t.peerOfferTitle)(mediumName(vm.peerOffer))} body={t.peerOfferBody}>
          <button className="secondary" onClick={vm.declinePeerOffer}>
            {t.stay}
          </button>
          <button className="primary" onClick={vm.acceptPeerOffer}>
            {t.join}
          </button>
        </Dialog>
      )}
      {askDraw && (
        <Dialog title={t.askToDrawTitle} body={t.askToDrawBody}>
          <button className="secondary" onClick={() => setAskDraw(false)}>
            {t.cancel}
          </button>
          <button
            className="primary"
            onClick={() => {
              setAskDraw(false);
              void vm.askToDraw();
            }}
          >
            {t.askToDraw}
          </button>
        </Dialog>
      )}
      {vm.drawRequest && (
        <Dialog title={t.drawRequestTitle} body={t.drawRequestBody}>
          <button className="secondary" onClick={() => void vm.answerDrawRequest(false)}>
            {t.decline}
          </button>
          <button className="primary" onClick={() => void vm.answerDrawRequest(true)}>
            {t.allow}
          </button>
        </Dialog>
      )}
      {confirmClear && (
        <Dialog title={t.clearBoardTitle}>
          <button className="secondary" onClick={() => setConfirmClear(false)}>
            {t.cancel}
          </button>
          <button
            className="primary"
            onClick={() => {
              setConfirmClear(false);
              void vm.clear();
            }}
          >
            {t.clearBoard}
          </button>
        </Dialog>
      )}
      {vm.drawDeclined && (
        <Dialog title={t.drawDeclined}>
          <button className="primary" onClick={vm.dismissDrawDeclined}>
            {t.ok}
          </button>
        </Dialog>
      )}
    </div>
  );
}

function RatingCard({ vm }: { vm: LessonModel }) {
  const { t } = useStrings();
  return (
    <section className="card center">
      <h2>{t.rateTitle(vm.peerName || t.yourTeacher)}</h2>
      {vm.lessonSeconds !== null && <p className="muted">{t.lessonLength(Math.max(1, Math.round(vm.lessonSeconds / 60)))}</p>}
      <div className="stars" role="radiogroup">
        {[1, 2, 3, 4, 5].map((n) => (
          <button
            key={n}
            className={n <= vm.rating ? "star on" : "star"}
            onClick={() => vm.setRating(n)}
            aria-label={String(n)}
            role="radio"
            aria-checked={n === vm.rating}
          >
            ★
          </button>
        ))}
      </div>
      <textarea dir="auto" rows={3} value={vm.comment} onChange={(e) => vm.setComment(e.target.value)} placeholder={t.ratingComment} />
      <button className="primary" onClick={vm.submitRating} disabled={!vm.rating || vm.ratingBusy}>
        {t.submitRating}
      </button>
      <button className="link" onClick={vm.skipRating}>
        {t.skip}
      </button>
    </section>
  );
}

function EndedCard({ vm, onFinished }: { vm: LessonModel; onFinished: () => void }) {
  const { t } = useStrings();
  return (
    <section className="card center">
      <h2>{vm.phase === "ending" ? t.endingLesson : t.lessonEnded}</h2>
      {vm.phase === "done" && vm.lessonSeconds !== null && (
        <p className="muted">{t.lessonLength(Math.max(1, Math.round(vm.lessonSeconds / 60)))}</p>
      )}
      {vm.phase === "done" && (
        <button className="primary" onClick={onFinished}>
          {t.done}
        </button>
      )}
    </section>
  );
}
