import { useState, type FormEvent } from "react";
import type { User } from "firebase/auth";
import { useStrings } from "../i18n";
import { STUDENT_GRADES, completeProfile, normalizePhone, type AccountRole, type StudentProfile } from "../services/account";

/** The onboarding profile step (CompleteProfileView): a name for everyone, a
 *  phone that a teacher must give and a student may, and a student's grade.
 *  Saving it saves the role, which finishes onboarding. A teacher reaches it
 *  after choosing subjects, as in the teacher app. */
export function CompleteProfile({ role, user, profile }: { role: AccountRole; user: User; profile: StudentProfile | null }) {
  const { t } = useStrings();
  // What is already known: a saved name, or the one Google or Apple gave.
  const [fullName, setFullName] = useState(() => profile?.fullName || user.displayName || "");
  const [phone, setPhone] = useState(() => profile?.phoneNumber ?? "");
  const [grade, setGrade] = useState(() => profile?.grade ?? "");
  const [busy, setBusy] = useState(false);
  const [failed, setFailed] = useState(false);

  const phoneGiven = phone.trim() !== "";
  const phoneValid = phoneGiven ? normalizePhone(phone) !== "" : role === "student";
  const canContinue = fullName.trim() !== "" && phoneValid && !busy;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!canContinue) return;
    setBusy(true);
    setFailed(false);
    try {
      // The profile listener sees the role and lets the dashboard in.
      await completeProfile(role, { fullName, phone, grade });
    } catch (err) {
      console.error("[completeProfile] save failed", err);
      setFailed(true);
      setBusy(false);
    }
  };

  return (
    <form className="card form" onSubmit={submit}>
      <h2>{t.completeProfileTitle}</h2>
      <p className="muted small">{t.completeProfileSubtitle}</p>

      <label className="field">
        <span className="label">{t.fullName} *</span>
        <input dir="auto" value={fullName} onChange={(e) => setFullName(e.target.value)} required autoComplete="name" />
      </label>

      <label className="field">
        <span className="label">{role === "teacher" ? `${t.phone} *` : t.phoneOptional}</span>
        <input
          type="tel"
          dir="ltr"
          value={phone}
          onChange={(e) => setPhone(e.target.value)}
          required={role === "teacher"}
          autoComplete="tel"
          aria-invalid={phoneGiven && !phoneValid}
        />
        {phoneGiven && !phoneValid && <span className="error small">{t.phoneInvalid}</span>}
      </label>

      {role === "student" && (
        <label className="field">
          <span className="label">{t.yourGrade}</span>
          <select value={grade} onChange={(e) => setGrade(e.target.value)}>
            <option value="">{t.chooseGrade}</option>
            {STUDENT_GRADES.map((g) => (
              <option key={g} value={g}>
                {t.grades[g] ?? g}
              </option>
            ))}
          </select>
        </label>
      )}

      {failed && <p className="error">{t.genericError}</p>}
      <button className="primary" type="submit" disabled={!canContinue}>
        {busy ? t.saving : t.continueLabel}
      </button>
    </form>
  );
}
