import { useEffect, useRef, useState } from "react";
import { useStrings } from "../i18n";
import {
  REPORT_REASONS,
  blockTeacher,
  fetchLessonArchive,
  reportTeacher,
  type LessonMessage,
  type ReportReason,
} from "../services/history";

/** What a finished lesson's sheet shows, from either side's history. */
export interface LessonSummary {
  questionId: string;
  title: string;
  questionText: string;
  photoUrls: string[];
  /** The other side: the teacher for a student, the student for a teacher. */
  otherName: string;
  at: number;
  durationSeconds: number;
  /** "Cost" for a student, "Earned" for a teacher; null when not known. */
  amount: string | null;
  conversationType: string;
  rating: number;
  /** Already loaded with the lesson, or fetched when the sheet opens. */
  messages?: LessonMessage[];
}

const clock = (seconds: number) => `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
const initials = (name: string) => name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase() || "?";

/** The lesson's details as LessonDetailView shows them: who and when, what it
 *  cost or earned and how long it ran, the original question with its photos,
 *  and the whole chat as it happened, board snapshots included. A student can
 *  report or block the teacher from here. */
export function LessonDetail({
  lesson,
  viewerRole,
  onClose,
}: {
  lesson: LessonSummary;
  viewerRole: "student" | "teacher";
  onClose: () => void;
}) {
  const { t, language } = useStrings();
  const locale = language === "hebrew" ? "he-IL" : "en-US";
  const [messages, setMessages] = useState<LessonMessage[] | null>(lesson.messages ?? null);
  const [medium, setMedium] = useState(lesson.conversationType);
  const [failed, setFailed] = useState(false);
  const [report, setReport] = useState(false);
  const closeButton = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    if (lesson.messages) return;
    fetchLessonArchive(lesson.questionId).then(
      (archive) => {
        setMessages(archive.messages);
        if (archive.conversationType) setMedium(archive.conversationType);
      },
      (e) => {
      console.error("[lessonDetail] messages failed", e);
        setFailed(true);
        setMessages([]);
      },
    );
  }, [lesson]);

  useEffect(() => {
    closeButton.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && !report && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose, report]);

  const when = lesson.at ? new Date(lesson.at).toLocaleString(locale, { dateStyle: "medium", timeStyle: "short" }) : "";
  const time = (ms: number) => (ms ? new Date(ms).toLocaleTimeString(locale, { hour: "2-digit", minute: "2-digit" }) : "");

  return (
    <div className="scrim legal-scrim" onClick={onClose}>
      <div className="legal-sheet detail-sheet" role="dialog" aria-modal="true" aria-label={t.lessonDetails} onClick={(e) => e.stopPropagation()}>
        <header>
          <h3>{t.lessonDetails}</h3>
          <button ref={closeButton} className="sheet-close" onClick={onClose} aria-label={t.close} title={t.close}>
            ✕
          </button>
        </header>

        <div className="detail-body">
          <div>
            <h2 className="detail-title">
              <bdi>{lesson.title}</bdi>
            </h2>
            <p className="muted small">
              {[lesson.otherName, when, clock(lesson.durationSeconds)].filter(Boolean).join(" • ")}
            </p>
          </div>

          <div className="metric-row">
            {lesson.amount !== null && (
              <div className="metric">
                <span aria-hidden>💳</span>
                <div>
                  <small>{viewerRole === "teacher" ? t.earnedLabel : t.costLabel}</small>
                  <strong>{lesson.amount}</strong>
                </div>
              </div>
            )}
            <div className="metric">
              <span aria-hidden>⏱</span>
              <div>
                <small>{t.durationLabel}</small>
                <strong>
                  <bdi>{clock(lesson.durationSeconds)}</bdi>
                </strong>
              </div>
            </div>
            <div className="metric">
              <span aria-hidden>💬</span>
              <div>
                <small>{t.mediumLabel}</small>
                <strong>{medium ? (t.mediums[medium] ?? medium) : "—"}</strong>
              </div>
            </div>
            <div className="metric">
              <span aria-hidden>★</span>
              <div>
                <small>{viewerRole === "teacher" ? t.studentsRating : t.yourRating}</small>
                <strong>{lesson.rating ? <span className="row-stars">{"★".repeat(lesson.rating)}</span> : t.notRated}</strong>
              </div>
            </div>
          </div>

          {viewerRole === "student" && (
            <button className="report-link" onClick={() => setReport(true)}>
              ⚑ {t.reportOrBlock(lesson.otherName || t.yourTeacher)}
            </button>
          )}

          {(lesson.questionText || lesson.photoUrls.length > 0) && (
            <div className="pinned detail-question">
              <span className="pin" aria-hidden>
                📌
              </span>
              <div>
                <div className="pinned-label">{t.originalQuestion}</div>
                {lesson.questionText && <div dir="auto">{lesson.questionText}</div>}
                {lesson.photoUrls.map((u) => (
                  <a key={u} href={u} target="_blank" rel="noreferrer">
                    <img className="question-photo" src={u} alt="" />
                  </a>
                ))}
              </div>
            </div>
          )}

          {lesson.otherName && (
            <div className="card summary">
              <strong>{t.summaryTitle}</strong>
              <p className="muted small">{t.completedLessonWith(lesson.otherName)}</p>
            </div>
          )}

          <div>
            <h3 className="section-title">{t.chatMessagesTitle}</h3>
            {messages === null ? (
              <div className="pulse small-pulse" />
            ) : messages.length === 0 ? (
              <p className="muted small">{failed ? t.loadFailed : t.noMessages}</p>
            ) : (
              <div className="history-thread">
                {messages.map((m) => {
                  const mine = m.senderRole === viewerRole;
                  return (
                    <div key={m.id} className={mine ? "row mine" : "row"}>
                      {!mine && <div className="avatar small">{initials(lesson.otherName)}</div>}
                      <div dir="auto" className={mine ? "bubble mine" : "bubble"}>
                        {m.kind === "image" ? (
                          <a href={m.text} target="_blank" rel="noreferrer">
                            <img className="message-image" src={m.text} alt={t.imageMessage} />
                          </a>
                        ) : m.kind === "audio" ? (
                          <a href={m.text} target="_blank" rel="noreferrer">
                            🎙 {t.audioMessage}
                          </a>
                        ) : m.kind === "video" ? (
                          <a href={m.text} target="_blank" rel="noreferrer">
                            🎥 {t.videoMessage}
                          </a>
                        ) : (
                          m.text
                        )}
                        <span className="bubble-time">
                          <bdi>{time(m.createdAt)}</bdi>
                        </span>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      </div>

      {report && (
        <ReportTeacher questionId={lesson.questionId} teacherName={lesson.otherName || t.yourTeacher} onClose={() => setReport(false)} />
      )}
    </div>
  );
}

type ReportState = "form" | "sending" | "confirmBlock" | "blocking" | "reported" | "blocked" | "failed";

/** Report or block the lesson's teacher (ReportTeacherView). */
function ReportTeacher({ questionId, teacherName, onClose }: { questionId: string; teacherName: string; onClose: () => void }) {
  const { t } = useStrings();
  const [reason, setReason] = useState<ReportReason | null>(null);
  const [details, setDetails] = useState("");
  const [alsoBlock, setAlsoBlock] = useState(false);
  const [state, setState] = useState<ReportState>("form");

  const send = async () => {
    if (!reason) return;
    setState("sending");
    try {
      await reportTeacher(questionId, reason, details, alsoBlock);
      setState(alsoBlock ? "blocked" : "reported");
    } catch (e) {
      console.error("[report] failed", e);
      setState("failed");
    }
  };
  const block = async () => {
    setState("blocking");
    try {
      await blockTeacher(questionId);
      setState("blocked");
    } catch (e) {
      console.error("[block] failed", e);
      setState("failed");
    }
  };

  return (
    <div className="scrim report-scrim" onClick={(e) => e.stopPropagation()}>
      <div className="dialog report" role="dialog" aria-modal="true" aria-label={t.reportOrBlock(teacherName)}>
        {state === "reported" || state === "blocked" ? (
          <>
            <h3>{t.thankYou}</h3>
            <p className="muted">{state === "blocked" ? t.blockedDone(teacherName) : t.reportedDone}</p>
            <div className="dialog-actions">
              <button className="primary" onClick={onClose}>
                {t.done}
              </button>
            </div>
          </>
        ) : state === "confirmBlock" || state === "blocking" ? (
          <>
            <h3>{t.blockConfirmTitle(teacherName)}</h3>
            <p className="muted">{t.blockExplain}</p>
            <div className="dialog-actions">
              <button className="secondary" onClick={() => setState("form")} disabled={state === "blocking"}>
                {t.cancel}
              </button>
              <button className="danger-button" onClick={block} disabled={state === "blocking"}>
                {t.block}
              </button>
            </div>
          </>
        ) : (
          <>
            <h3>{t.reportOrBlock(teacherName)}</h3>
            <span className="label">{t.whatHappened}</span>
            <div className="reasons" role="radiogroup">
              {REPORT_REASONS.map((r) => (
                <label key={r} className={reason === r ? "reason on" : "reason"}>
                  <input type="radio" name="reason" checked={reason === r} onChange={() => setReason(r)} />
                  {t.reportReasons[r]}
                </label>
              ))}
            </div>
            <textarea dir="auto" rows={3} maxLength={1000} value={details} onChange={(e) => setDetails(e.target.value)} placeholder={t.tellUsMore} />
            <label className="consent">
              <input type="checkbox" checked={alsoBlock} onChange={(e) => setAlsoBlock(e.target.checked)} />
              <span>
                {t.alsoBlock(teacherName)}
                <br />
                <small className="muted">{t.blockExplain}</small>
              </span>
            </label>
            <p className="muted small">{t.reviewPromise}</p>
            {state === "failed" && <p className="error">{t.reportFailed}</p>}
            <div className="dialog-actions spread">
              <button className="link danger-text" onClick={() => setState("confirmBlock")}>
                {t.blockWithoutReporting(teacherName)}
              </button>
              <div className="dialog-actions inline">
                <button className="secondary" onClick={onClose}>
                  {t.cancel}
                </button>
                <button className="primary" onClick={send} disabled={!reason || state === "sending"}>
                  {state === "sending" ? t.sending : t.sendReport}
                </button>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
