import { useState, type FormEvent } from "react";
import { FirebaseError } from "firebase/app";
import { useStrings } from "../i18n";
import { normalizePhone, signIn, signUpStudent, signUpTeacher, WrongRoleError, type AccountRole } from "../services/account";
import { LegalLink } from "./LegalViewer";

export function SignIn() {
  const { t } = useStrings();
  const [mode, setMode] = useState<"signIn" | "signUp">("signIn");
  const [role, setRole] = useState<AccountRole>(() => (localStorage.getItem("signIn.role") === "teacher" ? "teacher" : "student"));
  const chooseRole = (r: AccountRole) => {
    setRole(r);
    localStorage.setItem("signIn.role", r);
    setError(null);
  };
  const [phone, setPhone] = useState("");
  const phoneValid = role !== "teacher" || mode !== "signUp" || normalizePhone(phone) !== "";
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [agreed, setAgreed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    // An account is created only with the terms accepted, as on the apps.
    if (mode === "signUp" && (!agreed || !phoneValid)) return;
    setBusy(true);
    setError(null);
    try {
      if (mode === "signIn") await signIn(email, password, role);
      else if (role === "teacher") await signUpTeacher(fullName, email, password, phone);
      else await signUpStudent(fullName, email, password);
    } catch (err) {
      console.error("[signIn] failed", err);
      setError(
        err instanceof WrongRoleError
          ? err.actual === "student" ? t.wrongRoleStudent : t.wrongRoleTeacher
          : err instanceof FirebaseError ? err.code.replace("auth/", "") : t.genericError,
      );
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="card" onSubmit={submit}>
      <h2>{mode === "signIn" ? t.signIn : role === "teacher" ? t.createTeacherAccount : t.createAccount}</h2>
      <div className="role-picker" role="radiogroup" aria-label={t.signInAs}>
        {(["student", "teacher"] as AccountRole[]).map((r) => (
          <button
            key={r}
            type="button"
            role="radio"
            aria-checked={role === r}
            className={role === r ? "on" : ""}
            onClick={() => chooseRole(r)}
          >
            {r === "student" ? t.asStudent : t.asTeacher}
          </button>
        ))}
      </div>
      {mode === "signUp" && (
        <input dir="auto" value={fullName} onChange={(e) => setFullName(e.target.value)} placeholder={t.fullName} required autoComplete="name" />
      )}
      <input dir="auto" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder={t.email} required autoComplete="email" />
      <input
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        placeholder={t.password}
        required
        minLength={6}
        autoComplete={mode === "signIn" ? "current-password" : "new-password"}
      />
      {mode === "signUp" && role === "teacher" && (
        <>
          <input
            type="tel"
            dir="ltr"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
            placeholder={t.phone}
            required
            autoComplete="tel"
            aria-invalid={phone !== "" && !phoneValid}
          />
          {phone !== "" && !phoneValid && <p className="error small">{t.phoneInvalid}</p>}
        </>
      )}
      {mode === "signUp" && (
        <>
          <label className="consent">
            <input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} />
            <span>
              {t.agreePrefix}
              <LegalLink page="eula">{t.termsOfService}</LegalLink>
              {t.agreeJoin}
              <LegalLink page="privacy">{t.privacyPolicy}</LegalLink>
              {t.agreeSuffix}
            </span>
          </label>
          {!agreed && <p className="muted small hint">{t.acceptTermsHint}</p>}
        </>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <button className="primary" type="submit" disabled={busy || (mode === "signUp" && (!agreed || !phoneValid))}>
        {mode === "signIn" ? t.signIn : t.createAccount}
      </button>
      <button type="button" className="link" onClick={() => setMode(mode === "signIn" ? "signUp" : "signIn")}>
        {mode === "signIn" ? (role === "teacher" ? t.noTeacherAccount : t.noAccount) : t.haveAccount}
      </button>
    </form>
  );
}
