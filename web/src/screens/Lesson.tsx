import { useEffect, useRef } from "react";
import type { LocalTrack, RemoteTrack } from "livekit-client";
import { useStrings } from "../i18n";
import { useLesson, type LessonInput } from "./useLesson";

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

export function Lesson({ input, onFinished }: { input: LessonInput; onFinished: () => void }) {
  const { t } = useStrings();
  const vm = useLesson(input, onFinished);
  const bottom = useRef<HTMLDivElement>(null);
  // Braces matter: newer Chromium returns a Promise from scrollIntoView, and an
  // effect that returns anything but a cleanup function takes the page down.
  useEffect(() => {
    bottom.current?.scrollIntoView({ block: "end" });
  }, [vm.messages.length]);

  if (vm.phase === "rating") {
    return (
      <section className="card center">
        <h2>{t.rateTitle(vm.question?.teacherName || t.yourTeacher)}</h2>
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

  if (vm.phase === "done" || vm.phase === "ending") {
    return (
      <section className="card center">
        <h2>{vm.phase === "ending" ? t.endingLesson : t.lessonEnded}</h2>
        {vm.phase === "done" && (
          <button className="primary" onClick={onFinished}>
            {t.done}
          </button>
        )}
      </section>
    );
  }

  const remoteVideo = vm.remoteTracks.find((tr) => tr.kind === "video");
  const remoteAudio = vm.remoteTracks.filter((tr) => tr.kind === "audio");

  return (
    <section className="card lesson">
      <div className="lesson-head">
        <div>
          <strong>{vm.question?.teacherName || t.yourTeacher}</strong>
          <p className="muted small">
            {vm.phase === "connecting" ? t.connecting : vm.phase === "waitingForTeacher" ? t.waitingForTeacher : t.live}
          </p>
        </div>
        <div className="lesson-actions">
          {vm.hasMedia && !vm.mediaError && (
            <button className="secondary" onClick={vm.toggleMic}>
              {vm.micOn ? t.mute : t.unmute}
            </button>
          )}
          <button className="danger" onClick={vm.leave}>
            {t.endLesson}
          </button>
        </div>
      </div>

      {vm.mediaError && <p className="error">{t.mediaFailed}</p>}
      {vm.cameraFailed && <p className="muted small">{t.cameraFailed}</p>}

      {(remoteVideo || vm.localCamera) && (
        <div className="video-stage">
          {remoteVideo ? <TrackView track={remoteVideo} className="remote" /> : <div className="remote placeholder" />}
          {vm.localCamera && <TrackView track={vm.localCamera} muted className="self" />}
        </div>
      )}
      {remoteAudio.map((tr) => (
        <TrackView key={tr.sid} track={tr} />
      ))}

      <div className="messages">
        {vm.messages.map((m) => (
          <div key={m.id} dir="auto" className={m.senderUid === vm.uid ? "bubble mine" : "bubble"}>
            {m.text}
          </div>
        ))}
        <div ref={bottom} />
      </div>

      <form
        className="composer"
        onSubmit={(e) => {
          e.preventDefault();
          void vm.send();
        }}
      >
        <input dir="auto" value={vm.draft} onChange={(e) => vm.setDraft(e.target.value)} placeholder={t.messagePlaceholder} />
        <button className="primary" type="submit" disabled={!vm.draft.trim()}>
          {t.send}
        </button>
      </form>
    </section>
  );
}
