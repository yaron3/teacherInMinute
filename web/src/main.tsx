import { StrictMode, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import type { User } from "firebase/auth";
import { LanguageContext, initialLanguage, stringsFor, type Language } from "./i18n";
import { signOut, watchAuth, watchProfile, type StudentProfile } from "./services/account";
import { usingEmulators } from "./services/firebase";
import { SignIn } from "./screens/SignIn";
import { StudentHome } from "./screens/StudentHome";
import "./styles.css";

function App() {
  const [language, setLanguage] = useState<Language>(initialLanguage);
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [profile, setProfile] = useState<StudentProfile | null>(null);

  useEffect(() => watchAuth(setUser), []);
  useEffect(() => {
    if (!user) return setProfile(null);
    return watchProfile(user.uid, setProfile);
  }, [user]);

  useEffect(() => {
    localStorage.setItem("settings.language.preference", language);
    document.documentElement.lang = language === "hebrew" ? "he" : "en";
    document.documentElement.dir = language === "hebrew" ? "rtl" : "ltr";
  }, [language]);

  const ctx = useMemo(
    () => ({
      language,
      t: stringsFor(language),
      toggle: () => setLanguage((l) => (l === "hebrew" ? "english" : "hebrew")),
    }),
    [language],
  );
  const { t } = ctx;

  return (
    <LanguageContext.Provider value={ctx}>
      {usingEmulators && <div className="dev-banner">{t.devBanner}</div>}
      <header className="top">
        <div>
          <h1>{t.appName}</h1>
          <p className="muted">{t.tagline}</p>
        </div>
        <div className="top-actions">
          <button className="link" onClick={ctx.toggle}>
            {t.language}
          </button>
          {user && (
            <button className="link" onClick={() => signOut()}>
              {t.signOut}
            </button>
          )}
        </div>
      </header>
      <main>{user === undefined ? null : user ? <StudentHome profile={profile} /> : <SignIn />}</main>
    </LanguageContext.Provider>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
