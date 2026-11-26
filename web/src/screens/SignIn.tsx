import { useState, type FormEvent } from "react";
import { FirebaseError } from "firebase/app";
import { useStrings } from "../i18n";
import { signIn, signUpStudent } from "../services/account";

export function SignIn() {
  const { t } = useStrings();
  const [mode, setMode] = useState<"signIn" | "signUp">("signIn");
  const [fullName, setFullName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      if (mode === "signIn") await signIn(email, password);
      else await signUpStudent(fullName, email, password);
    } catch (err) {
      console.error("[signIn] failed", err);
      setError(err instanceof FirebaseError ? err.code.replace("auth/", "") : t.genericError);
    } finally {
      setBusy(false);
    }
  };

  return (
    <form className="card" onSubmit={submit}>
      <h2>{mode === "signIn" ? t.signIn : t.createAccount}</h2>
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
      {error && (
        <p className="error" role="alert">
          {error}
        </p>
      )}
      <button className="primary" type="submit" disabled={busy}>
        {mode === "signIn" ? t.signIn : t.createAccount}
      </button>
      <button type="button" className="link" onClick={() => setMode(mode === "signIn" ? "signUp" : "signIn")}>
        {mode === "signIn" ? t.noAccount : t.haveAccount}
      </button>
    </form>
  );
}
