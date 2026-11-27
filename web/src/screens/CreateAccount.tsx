import { useEffect, useState } from "react";
import { useStrings } from "../i18n";
import { SignIn, type SignInMode } from "./SignIn";

/** What an anonymous student sees where an account is needed (minutes,
 *  purchases, keeping their lessons): why, a "Create a user account" button,
 *  and a way to log in to the account they already have. Either opens the
 *  sign-up sheet; creating the account links it to this one, so the question
 *  being written and the lessons so far stay. */
export function CreateAccountPrompt({ message, title }: { message: string; title?: string }) {
  const { t } = useStrings();
  const [sheet, setSheet] = useState<SignInMode | null>(null);
  return (
    <div className="create-account">
      {title && <strong>{title}</strong>}
      <p className="muted">{message}</p>
      <button className="primary" onClick={() => setSheet("signUp")}>
        {t.createUserAccount}
      </button>
      <span className="muted small">
        {t.alreadyHaveAccount}{" "}
        <button type="button" className="link small" onClick={() => setSheet("signIn")}>
          {t.logIn}
        </button>
      </span>
      {sheet && <CreateAccountSheet mode={sheet} onClose={() => setSheet(null)} />}
    </div>
  );
}

function CreateAccountSheet({ mode, onClose }: { mode: SignInMode; onClose: () => void }) {
  const { t } = useStrings();
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <div className="scrim" onClick={onClose}>
      <div className="dialog account-sheet" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
        <button className="sheet-close" onClick={onClose} aria-label={t.close} title={t.close}>
          ✕
        </button>
        <SignIn studentOnly initialMode={mode} />
      </div>
    </div>
  );
}
