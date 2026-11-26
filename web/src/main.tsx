import { StrictMode, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import type { User } from "firebase/auth";
import { LanguageContext, initialLanguage, stringsFor, type Language } from "./i18n";
import { signOut, watchAuth, watchProfile, watchRoleCheck, type StudentProfile } from "./services/account";
import { usingEmulators } from "./services/firebase";
import { SignIn } from "./screens/SignIn";
import { StudentHome } from "./screens/StudentHome";
import { LessonsScreen } from "./screens/LessonsScreen";
import { BuyMinutes } from "./screens/BuyMinutes";
import { ProfileScreen } from "./screens/ProfileScreen";
import { HelpScreen } from "./screens/HelpScreen";
import { TeacherHome } from "./screens/TeacherHome";
import { TeacherEarnings, TeacherLessons } from "./screens/TeacherEarnings";
import { LegalLink, LegalProvider } from "./screens/LegalViewer";
import "./styles.css";

type Page = "home" | "lessons" | "buy" | "earnings" | "profile" | "help";
const ALL_PAGES: Page[] = ["home", "lessons", "buy", "earnings", "profile", "help"];
/** A student buys minutes; a teacher sees what they earned. */
const STUDENT_PAGES: Page[] = ["home", "lessons", "buy", "profile", "help"];
const TEACHER_PAGES: Page[] = ["home", "lessons", "earnings", "profile", "help"];
const ICONS: Record<Page, string> = { home: "✦", lessons: "☰", buy: "＋", earnings: "₪", profile: "◉", help: "?" };

/** The page lives in the URL hash, so the browser's back button moves between them. */
function usePage(): [Page, (p: Page) => void] {
  const read = (): Page => {
    const h = location.hash.replace("#", "") as Page;
    return ALL_PAGES.includes(h) ? h : "home";
  };
  const [page, setPage] = useState<Page>(read);
  useEffect(() => {
    const onHash = () => setPage(read());
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  }, []);
  return [page, (p) => (location.hash = p === "home" ? "" : p)];
}

function App() {
  const [language, setLanguage] = useState<Language>(initialLanguage);
  const [user, setUser] = useState<User | null | undefined>(undefined);
  const [profile, setProfile] = useState<StudentProfile | null>(null);
  const [checkingRole, setCheckingRole] = useState(false);
  useEffect(() => watchRoleCheck(setCheckingRole), []);

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

  const [page, go] = usePage();
  const isTeacherLabel = profile?.role === "teacher";
  const label: Record<Page, string> = { home: isTeacherLabel ? t.navTeach : t.navHome, lessons: t.navLessons, buy: t.navBuy, earnings: t.navEarnings, profile: t.navProfile, help: t.navHelp };

  if (user === undefined) return null;

  if (!user || checkingRole) {
    return (
      <LanguageContext.Provider value={ctx}>
      <LegalProvider>
        {usingEmulators && <div className="dev-banner">{t.devBanner}</div>}
        <div className="narrow">
          <header className="top">
            <div>
              <h1>{t.appName}</h1>
              <p className="muted">{t.tagline}</p>
            </div>
            <div className="top-actions">
              <button className="link" onClick={ctx.toggle}>
                {t.language}
              </button>
            </div>
          </header>
          <main>
            <SignIn />
          </main>
          <footer className="legal-foot">
            <LegalLink page="eula">{t.termsOfService}</LegalLink>
            <LegalLink page="privacy">{t.privacyPolicy}</LegalLink>
          </footer>
        </div>
            </LegalProvider>
    </LanguageContext.Provider>
    );
  }

  // The dashboard is drawn for the account's role, so it waits for the profile.
  if (!profile) return null;
  const isTeacher = profile.role === "teacher";
  const PAGES = isTeacher ? TEACHER_PAGES : STUDENT_PAGES;
  const shown: Page = PAGES.includes(page) ? page : "home";

  return (
    <LanguageContext.Provider value={ctx}>
      <LegalProvider>
      {usingEmulators && <div className="dev-banner">{t.devBanner}</div>}
      <div className="shell">
        <nav className="sidebar" aria-label={t.appName}>
          <div className="brand">
            <img src="/icons/icon-192.png" alt="" />
            <strong>{t.appName}</strong>
          </div>
          {isTeacher ? (
            <div className="role-chip">{t.teacherRole}</div>
          ) : (
            <button className="balance-chip" onClick={() => go("buy")} aria-label={`${t.minutesBalance}: ${profile.remainingMinutes}. ${t.navBuy}`}>
              <span>{t.minutesBalance}</span>
              <strong>{profile.remainingMinutes}</strong>
            </button>
          )}
          <ul>
            {PAGES.map((p) => (
              <li key={p}>
                <button className={shown === p ? "nav-item on" : "nav-item"} aria-current={shown === p ? "page" : undefined} onClick={() => go(p)}>
                  <span className="nav-icon" aria-hidden>
                    {ICONS[p]}
                  </span>
                  {label[p]}
                </button>
              </li>
            ))}
          </ul>
          <div className="sidebar-legal">
            <LegalLink page="eula">{t.termsOfService}</LegalLink>
            <LegalLink page="privacy">{t.privacyPolicy}</LegalLink>
          </div>
          <div className="sidebar-foot">
            <button className="link" onClick={ctx.toggle}>
              {t.language}
            </button>
            <button className="link" onClick={() => signOut()}>
              {t.signOut}
            </button>
          </div>
        </nav>

        <main className="content">
          {/* Kept mounted, so a search, a lesson, or a teacher's time online carries
              on while other pages are open. */}
          {isTeacher ? (
            <div hidden={shown !== "home"}>
              <TeacherHome key={user.uid} profile={profile} />
            </div>
          ) : (
            <div hidden={shown !== "home"} className="narrow">
              <StudentHome profile={profile} />
            </div>
          )}
          {shown === "lessons" && (isTeacher ? <TeacherLessons /> : <LessonsScreen />)}
          {shown === "buy" && <BuyMinutes remainingMinutes={profile.remainingMinutes} />}
          {shown === "earnings" && <TeacherEarnings />}
          {shown === "profile" && <ProfileScreen profile={profile} />}
          {shown === "help" && <HelpScreen profile={profile} />}
        </main>

        <nav className="tabbar" aria-label={t.appName}>
          {PAGES.map((p) => (
            <button key={p} className={shown === p ? "on" : ""} aria-current={shown === p ? "page" : undefined} onClick={() => go(p)}>
              <span aria-hidden>{ICONS[p]}</span>
              {label[p]}
            </button>
          ))}
        </nav>
      </div>
          </LegalProvider>
    </LanguageContext.Provider>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
