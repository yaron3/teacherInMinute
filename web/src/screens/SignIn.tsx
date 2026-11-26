import { useEffect, useState, type FormEvent } from "react";
import { useStrings } from "../i18n";
import {
  WrongRoleError,
  appleSignInEnabled,
  authErrorKey,
  chosenRole,
  resetPassword,
  setChosenRole,
  signIn,
  signInWithProvider,
  signUp,
  startAnonymously,
  type AccountRole,
} from "../services/account";
import { fetchPromotion, type Promotion } from "../services/promotion";
import { LegalLink } from "./LegalViewer";

export type SignInMode = "intro" | "signIn" | "signUp" | "reset";

/** The way in, as the two apps have it: the student app opens on an intro
 *  that lets a student start without an account (StudentIntroView); then
 *  log in (LoginView), create an account (CreateAccountView) and reset the
 *  password (ResetPasswordView). The web serves both apps, so a picker says
 *  which side is signing in.
 *
 *  `studentOnly` is the create-account sheet an anonymous student opens from
 *  inside the app: no picker, no intro. */
export function SignIn({ initialMode, studentOnly = false }: { initialMode?: SignInMode; studentOnly?: boolean }) {
  const { t, language } = useStrings();
  const [role, setRole] = useState<AccountRole>(() => (studentOnly ? "student" : chosenRole()));
  const [mode, setMode] = useState<SignInMode>(() => initialMode ?? (role === "student" ? "intro" : "signIn"));
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [agreed, setAgreed] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  const chooseRole = (r: AccountRole) => {
    setRole(r);
    setChosenRole(r);
    setError(null);
    if (r === "teacher" && mode === "intro") setMode("signIn");
  };
  const switchTo = (m: SignInMode) => {
    setMode(m);
    setError(null);
    setInfo(null);
  };

  const describe = (err: unknown): string | null => {
    if (err instanceof WrongRoleError) return err.actual === "student" ? t.wrongRoleStudent : t.wrongRoleTeacher;
    const key = authErrorKey(err);
    return key === "popupClosed" ? null : t.authErrors[key];
  };

  const run = async (work: () => Promise<void>) => {
    setBusy(true);
    setError(null);
    setInfo(null);
    try {
      await work();
    } catch (err) {
      console.error("[signIn] failed", err);
      setError(describe(err));
    } finally {
      setBusy(false);
    }
  };

  const mismatch = mode === "signUp" && confirm !== "" && confirm !== password;
  const canCreate = agreed && password.length >= 6 && confirm === password;

  const submit = (e: FormEvent) => {
    e.preventDefault();
    if (mode === "reset") {
      if (!email.trim()) return setError(t.enterEmailFirst);
      return run(async () => {
        await resetPassword(email, language);
        setInfo(t.resetSent);
      });
    }
    if (mode === "signUp") {
      // An account is created only with the terms accepted, as on the apps.
      if (!canCreate) return;
      return run(() => signUp(email, password, role));
    }
    return run(() => signIn(email, password, role));
  };

  if (mode === "intro") return <Intro onStart={() => run(startAnonymously)} onLogIn={() => switchTo("signIn")} onTeacher={() => chooseRole("teacher")} busy={busy} error={error} />;

  const title =
    mode === "reset" ? t.resetTitle : mode === "signIn" ? t.signIn : role === "teacher" ? t.createTeacherAccount : t.createAccount;

  return (
    <form className={studentOnly ? "form" : "card form"} onSubmit={submit}>
      <h2>{title}</h2>
      {!studentOnly && mode !== "reset" && (
        <div className="role-picker" role="radiogroup" aria-label={t.signInAs}>
          {(["student", "teacher"] as AccountRole[]).map((r) => (
            <button key={r} type="button" role="radio" aria-checked={role === r} className={role === r ? "on" : ""} onClick={() => chooseRole(r)}>
              {r === "student" ? t.asStudent : t.asTeacher}
            </button>
          ))}
        </div>
      )}
      {mode === "reset" && <p className="muted small">{t.resetHint}</p>}

      <input dir="auto" type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder={t.email} required autoComplete="email" />
      {mode !== "reset" && (
        <input
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder={t.password}
          required
          minLength={6}
          autoComplete={mode === "signIn" ? "current-password" : "new-password"}
        />
      )}
      {mode === "signUp" && (
        <>
          <input
            type="password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            placeholder={t.confirmPassword}
            required
            autoComplete="new-password"
            aria-invalid={mismatch}
          />
          {mismatch && <p className="error small">{t.passwordsDontMatch}</p>}
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
      {info && (
        <p className="success" role="status">
          {info}
        </p>
      )}

      <button className="primary" type="submit" disabled={busy || (mode === "signUp" && !canCreate)}>
        {mode === "reset" ? t.sendResetLink : mode === "signIn" ? t.signIn : t.createAccount}
      </button>

      {mode === "signIn" && (
        <button type="button" className="link small" onClick={() => switchTo("reset")}>
          {t.forgotPassword}
        </button>
      )}

      {mode !== "reset" && (
        <div className="social">
          <span className="muted small">{t.orContinueWith}</span>
          <div className="social-buttons">
            <button type="button" className="secondary" disabled={busy} onClick={() => run(() => signInWithProvider("google", role))}>
              <span aria-hidden className="social-mark">G</span> {t.google}
            </button>
            {appleSignInEnabled && (
              <button type="button" className="secondary" disabled={busy} onClick={() => run(() => signInWithProvider("apple", role))}>
                <span aria-hidden className="social-mark"></span> {t.apple}
              </button>
            )}
          </div>
        </div>
      )}

      {mode === "reset" ? (
        <button type="button" className="link" onClick={() => switchTo("signIn")}>
          {t.backToLogIn}
        </button>
      ) : (
        <button type="button" className="link" onClick={() => switchTo(mode === "signIn" ? "signUp" : "signIn")}>
          {mode === "signIn" ? (role === "teacher" ? t.noTeacherAccount : t.noAccount) : t.haveAccount}
        </button>
      )}
      {!studentOnly && role === "student" && mode === "signIn" && (
        <button type="button" className="link small" onClick={() => switchTo("intro")}>
          {language === "hebrew" ? "→" : "←"} {t.getStarted}
        </button>
      )}
    </form>
  );
}

/** StudentIntroView: the pitch, what it costs, the free minutes on offer, and
 *  a start that needs no account. */
function Intro({
  onStart,
  onLogIn,
  onTeacher,
  busy,
  error,
}: {
  onStart: () => void;
  onLogIn: () => void;
  onTeacher: () => void;
  busy: boolean;
  error: string | null;
}) {
  const { t } = useStrings();
  const [promotion, setPromotion] = useState<Promotion | null>(null);
  useEffect(() => {
    void fetchPromotion().then(setPromotion);
  }, []);

  return (
    <section className="card intro">
      <h2 className="intro-headline">
        {t.introStuck} <span className="accent">{t.introHumanTeacher}</span> {t.introWithin}
      </h2>
      <p className="muted">{t.introPitch}</p>
      {promotion && promotion.minutes > 0 && promotion.slots !== null && (
        <p className="pill promo">{t.introPromotion(promotion.minutes, promotion.slots)}</p>
      )}
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <button className="primary" onClick={onStart} disabled={busy}>
        {t.getStarted}
      </button>
      <p className="muted small center-text">{t.introPrice}</p>
      <div className="intro-links">
        <span className="muted small">
          {t.alreadyHaveAccount}{" "}
          <button type="button" className="link small" onClick={onLogIn}>
            {t.logIn}
          </button>
        </span>
        <span className="muted small">
          {t.areYouTeacher}{" "}
          <button type="button" className="link small" onClick={onTeacher}>
            {t.teacherEntry}
          </button>
        </span>
      </div>
    </section>
  );
}
