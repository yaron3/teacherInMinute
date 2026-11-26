import { useCallback, useEffect, useState } from "react";
import { useStrings } from "../i18n";
import { auth } from "../services/firebase";
import { billedMinutes, fetchLessons, type PastLesson } from "../services/history";
import { formatPrice } from "../services/purchase";

type Load = { kind: "loading" } | { kind: "failed" } | { kind: "ready"; lessons: PastLesson[] };

function duration(seconds: number) {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

/** The student's past lessons (StudentLessonHistoryViewModel), newest first,
 *  with what they add up to. */
export function LessonsScreen() {
  const { t, language } = useStrings();
  const locale = language === "hebrew" ? "he-IL" : "en-US";
  const [load, setLoad] = useState<Load>({ kind: "loading" });
  const [open, setOpen] = useState<PastLesson | null>(null);

  const reload = useCallback(async () => {
    const uid = auth.currentUser?.uid;
    if (!uid) return;
    setLoad({ kind: "loading" });
    try {
      setLoad({ kind: "ready", lessons: await fetchLessons(uid) });
    } catch (e) {
      console.error("[lessons] load failed", e);
      setLoad({ kind: "failed" });
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  const date = (ms: number) =>
    ms ? new Date(ms).toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" }) : "—";
  const cost = (l: PastLesson) => (l.costCents === null ? "—" : formatPrice(l.costCents, l.currency, locale));
  const title = (l: PastLesson) => l.title || t.topics[l.topic as keyof typeof t.topics] || t.lessonDetails;

  return (
    <section className="page">
      <h2 className="page-title">{t.lessonsTitle}</h2>

      {load.kind === "loading" && <div className="pulse small-pulse" aria-label={t.connecting} />}
      {load.kind === "failed" && (
        <div className="card center">
          <p>{t.loadFailed}</p>
          <button className="secondary" onClick={reload}>
            {t.retry}
          </button>
        </div>
      )}

      {load.kind === "ready" && (
        <>
          <div className="stats">
            <div className="stat">
              <strong>{load.lessons.length}</strong>
              <span>{t.statLessons}</span>
            </div>
            <div className="stat">
              <strong>{load.lessons.reduce((sum, l) => sum + billedMinutes(l.durationSeconds), 0)}</strong>
              <span>{t.statMinutes}</span>
            </div>
            <div className="stat">
              <strong>{new Set(load.lessons.map((l) => l.teacherName).filter(Boolean)).size}</strong>
              <span>{t.statTeachers}</span>
            </div>
          </div>

          {load.lessons.length === 0 ? (
            <div className="card center">
              <p className="muted">{t.noLessons}</p>
            </div>
          ) : (
            <ul className="lesson-list">
              {load.lessons.map((l) => (
                <li key={l.questionId}>
                  <button className="lesson-row" onClick={() => setOpen(l)}>
                    <div className="lesson-row-main">
                      <strong>
                        <bdi>{title(l)}</bdi>
                      </strong>
                      <span className="muted small">
                        {l.teacherName ? `${t.lessonWith(l.teacherName)} · ` : ""}
                        {date(l.at)}
                      </span>
                    </div>
                    <div className="lesson-row-side">
                      <span>{t.minutesShort(billedMinutes(l.durationSeconds))}</span>
                      <span className="muted small">{cost(l)}</span>
                    </div>
                    {l.rating > 0 && <span className="row-stars" aria-label={`${l.rating}/5`}>{"★".repeat(l.rating)}</span>}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </>
      )}

      {open && (
        <div className="scrim" role="dialog" aria-modal="true" aria-label={t.lessonDetails} onClick={() => setOpen(null)}>
          <div className="dialog details" onClick={(e) => e.stopPropagation()}>
            <h3>{t.lessonDetails}</h3>
            <dl>
              <dt>{t.questionLabel}</dt>
              <dd dir="auto" className="question-text">{open.questionText || title(open)}</dd>
              {open.photoUrls.length > 0 && (
                <dd className="photos">
                  {open.photoUrls.map((u) => (
                    <a key={u} href={u} target="_blank" rel="noreferrer">
                      <img src={u} alt="" />
                    </a>
                  ))}
                </dd>
              )}
              <dt>{t.teacherLabel}</dt>
              <dd>{open.teacherName || "—"}</dd>
              <dt>{t.dateLabel}</dt>
              <dd>{open.at ? new Date(open.at).toLocaleString(locale, { dateStyle: "medium", timeStyle: "short" }) : "—"}</dd>
              <dt>{t.durationLabel}</dt>
              <dd>
                <bdi>{duration(open.durationSeconds)}</bdi> · {t.minutesShort(billedMinutes(open.durationSeconds))}
              </dd>
              <dt>{t.costLabel}</dt>
              <dd>{cost(open)}</dd>
              <dt>{t.mediumLabel}</dt>
              <dd>{t.mediums[open.conversationType] ?? open.conversationType}</dd>
              <dt>{t.yourRating}</dt>
              <dd>{open.rating ? <span className="row-stars">{"★".repeat(open.rating)}</span> : t.notRated}</dd>
            </dl>
            <div className="dialog-actions">
              <button className="primary" onClick={() => setOpen(null)}>
                {t.close}
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
