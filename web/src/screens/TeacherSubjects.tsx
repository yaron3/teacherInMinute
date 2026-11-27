import { useState } from "react";
import { useStrings } from "../i18n";
import { auth } from "../services/firebase";
import { SUBJECT_CATALOG, saveSubjects, subjectKey } from "../services/teacher";

/** The subjects a teacher takes questions in (TeacherSubjectsView): an area,
 *  then at least one of its subtopics. The onboarding step after sign-up, and
 *  the editor behind Profile. */
export function TeacherSubjects({
  current,
  onSaved,
  onCancel,
}: {
  /** What is saved now: area → subtopic keys. */
  current: Record<string, string[]>;
  onSaved: () => void;
  /** Set when editing; onboarding has no way back. */
  onCancel?: () => void;
}) {
  const { t } = useStrings();
  // Saved keys can be "algebra" or "Algebra": compare on the key form.
  const [picked, setPicked] = useState<Record<string, Set<string>>>(() =>
    Object.fromEntries(
      SUBJECT_CATALOG.map(({ area, subtopics }) => {
        const saved = new Set((current[area] ?? []).map(subjectKey));
        return [area, new Set(subtopics.filter((s) => saved.has(subjectKey(s))))];
      }),
    ),
  );
  const [saving, setSaving] = useState(false);
  const [failed, setFailed] = useState(false);

  const count = Object.values(picked).reduce((n, s) => n + s.size, 0);
  const toggle = (area: string, sub: string) =>
    setPicked((p) => {
      const next = new Set(p[area]);
      if (next.has(sub)) next.delete(sub);
      else next.add(sub);
      return { ...p, [area]: next };
    });
  const allIn = (area: string, subs: string[]) => setPicked((p) => ({ ...p, [area]: p[area].size === subs.length ? new Set() : new Set(subs) }));

  const save = async () => {
    const uid = auth.currentUser?.uid;
    if (!uid || count === 0) return;
    setSaving(true);
    setFailed(false);
    try {
      await saveSubjects(uid, Object.fromEntries(Object.entries(picked).map(([a, s]) => [a, [...s]])));
      onSaved();
    } catch (e) {
      console.error("[subjects] save failed", e);
      setFailed(true);
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="card form subjects-editor">
      <h3 className="section-title">{t.chooseSubjects}</h3>
      <p className="muted small">{t.chooseSubjectsHint}</p>
      {SUBJECT_CATALOG.map(({ area, subtopics }) => (
        <div key={area} className="subject-area">
          <div className="subject-area-head">
            <strong>{t.subjectAreas[area] ?? area}</strong>
            <button type="button" className="link small" onClick={() => allIn(area, subtopics)}>
              {picked[area].size === subtopics.length ? t.clearAll : t.selectAll}
            </button>
          </div>
          <div className="chips">
            {subtopics.map((sub) => {
              const on = picked[area].has(sub);
              return (
                <button
                  key={sub}
                  type="button"
                  role="checkbox"
                  aria-checked={on}
                  className={on ? "chip selected" : "chip"}
                  onClick={() => toggle(area, sub)}
                >
                  {on ? "✓ " : ""}
                  {t.topics[subjectKey(sub) as keyof typeof t.topics] ?? sub}
                </button>
              );
            })}
          </div>
        </div>
      ))}
      {failed && <p className="error">{t.genericError}</p>}
      <div className="form-actions">
        <span className="muted small">{count === 0 ? t.pickAtLeastOne : t.subjectsPicked(count)}</span>
        {onCancel && (
          <button type="button" className="secondary" onClick={onCancel} disabled={saving}>
            {t.cancel}
          </button>
        )}
        <button type="button" className="primary" onClick={save} disabled={count === 0 || saving}>
          {saving ? t.saving : onCancel ? t.save : t.continueLabel}
        </button>
      </div>
    </div>
  );
}
