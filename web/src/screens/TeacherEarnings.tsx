import { useCallback, useEffect, useState } from "react";
import { useStrings } from "../i18n";
import { formatPrice } from "../services/purchase";
import { fetchEarnings, type EarningsSummary, type TeacherLesson } from "../services/teacher";
import { LessonDetail } from "./LessonDetail";

type Load = { kind: "loading" } | { kind: "failed" } | { kind: "ready"; summary: EarningsSummary };

function useEarnings() {
  const [load, setLoad] = useState<Load>({ kind: "loading" });
  const reload = useCallback(async () => {
    setLoad({ kind: "loading" });
    try {
      setLoad({ kind: "ready", summary: await fetchEarnings() });
    } catch (e) {
      console.error("[earnings] load failed", e);
      setLoad({ kind: "failed" });
    }
  }, []);
  useEffect(() => {
    void reload();
  }, [reload]);
  return { load, reload };
}

function Status({ load, reload }: { load: Load; reload: () => void }) {
  const { t } = useStrings();
  if (load.kind === "loading") return <div className="pulse small-pulse" />;
  if (load.kind === "failed")
    return (
      <div className="card center">
        <p>{t.loadFailed}</p>
        <button className="secondary" onClick={reload}>
          {t.retry}
        </button>
      </div>
    );
  return null;
}

const firstLine = (text: string) => text.split("\n").map((l) => l.trim()).find(Boolean) ?? "";

/** The teacher's past lessons (TeacherLessonHistoryView), from the same
 *  summary as the earnings, newest first. */
export function TeacherLessons() {
  const { t, language } = useStrings();
  const locale = language === "hebrew" ? "he-IL" : "en-US";
  const { load, reload } = useEarnings();
  const [open, setOpen] = useState<TeacherLesson | null>(null);
  const money = (cents: number, currency: string) => formatPrice(cents, currency || "ILS", locale);
  const date = (iso: string) => (iso ? new Date(iso).toLocaleDateString(locale, { day: "numeric", month: "short", year: "numeric" }) : "—");
  const title = (l: TeacherLesson) => firstLine(l.text) || t.topics[l.topic as keyof typeof t.topics] || l.topic || t.lessonDetails;

  return (
    <section className="page">
      <h2 className="page-title">{t.lessonsTitle}</h2>
      <Status load={load} reload={reload} />
      {load.kind === "ready" &&
        (load.summary.lessons.length === 0 ? (
          <div className="card center">
            <p className="muted">{t.noLessons}</p>
          </div>
        ) : (
          <ul className="lesson-list">
            {load.summary.lessons.map((l) => (
              <li key={l.questionId}>
                <button className="lesson-row" onClick={() => setOpen(l)}>
                  <div className="lesson-row-main">
                    <strong>
                      <bdi>{title(l)}</bdi>
                    </strong>
                    <span className="muted small">
                      {l.studentName ? `${t.lessonWith(l.studentName)} · ` : ""}
                      {date(l.acceptedAt)}
                    </span>
                  </div>
                  <div className="lesson-row-side">
                    <span>{t.minutesShort(Math.round(l.lessonSeconds / 60))}</span>
                    <span className="earned small">{money(l.earningsCents, l.currency || load.summary.currency)}</span>
                  </div>
                  {l.studentRating > 0 && <span className="row-stars">{"★".repeat(l.studentRating)}</span>}
                </button>
              </li>
            ))}
          </ul>
        ))}

      {open && load.kind === "ready" && (
        <LessonDetail
          viewerRole="teacher"
          onClose={() => setOpen(null)}
          lesson={{
            questionId: open.questionId,
            title: title(open),
            questionText: open.text,
            photoUrls: open.photoUrls,
            otherName: open.studentName,
            at: Date.parse(open.acceptedAt) || 0,
            durationSeconds: open.lessonSeconds,
            amount: money(open.earningsCents, open.currency || load.summary.currency),
            conversationType: "",
            rating: open.studentRating,
          }}
        />
      )}
    </section>
  );
}

/** What the teacher has earned (TeacherEarningsView): the total, the next
 *  payout, and month by month. */
export function TeacherEarnings() {
  const { t, language } = useStrings();
  const locale = language === "hebrew" ? "he-IL" : "en-US";
  const { load, reload } = useEarnings();

  return (
    <section className="page">
      <h2 className="page-title">{t.navEarnings}</h2>
      <Status load={load} reload={reload} />
      {load.kind === "ready" && (() => {
        const s = load.summary;
        const money = (cents: number) => formatPrice(cents, s.currency, locale);
        const months = [...s.months].reverse();
        const best = Math.max(1, ...s.months.map((m) => m.earningsCents));
        return (
          <>
            <div className="stats">
              <div className="stat">
                <strong>{money(s.totalEarningsCents)}</strong>
                <span>{t.totalEarned}</span>
              </div>
              <div className="stat">
                <strong>{s.lessons.length}</strong>
                <span>{t.statLessons}</span>
              </div>
              <div className="stat">
                <strong>{s.months.reduce((sum, m) => sum + m.minutesCount, 0)}</strong>
                <span>{t.statMinutesTaught}</span>
              </div>
            </div>

            {s.nextPayment && (
              <div className="card payout">
                <span className="muted">{t.nextPayout}</span>
                <strong>{money(s.nextPayment.amountCents)}</strong>
                <span className="muted small">
                  {t.payoutOn(new Date(s.nextPayment.payoutDate).toLocaleDateString(locale, { day: "numeric", month: "long", year: "numeric" }))}
                  {s.payoutMethodSummary ? ` · ${s.payoutMethodSummary}` : ""}
                </span>
              </div>
            )}

            <h3 className="section-title">{t.byMonth}</h3>
            {months.length === 0 ? (
              <div className="card center">
                <p className="muted">{t.noLessons}</p>
              </div>
            ) : (
              <ul className="month-list">
                {months.map((m) => (
                  <li key={m.id} className="month">
                    <span>{new Date(Date.UTC(m.year, m.month - 1, 1)).toLocaleDateString(locale, { month: "long", year: "numeric", timeZone: "UTC" })}</span>
                    <div className="bar" aria-hidden>
                      <span style={{ width: `${(m.earningsCents / best) * 100}%` }} />
                    </div>
                    <span className="muted small">
                      {m.lessonCount} · {t.minutesShort(m.minutesCount)}
                    </span>
                    <strong>{money(m.earningsCents)}</strong>
                  </li>
                ))}
              </ul>
            )}
          </>
        );
      })()}
    </section>
  );
}
