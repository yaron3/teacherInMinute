import React, { StrictMode, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import type { User } from "firebase/auth";
import { LanguageContext, initialLanguage, stringsFor, useStrings, type Language } from "./i18n";
import { resumeRoute, saveAnonymousStudentProfile, signOut, watchAuth, watchProfile, watchRoleCheck, type StudentProfile } from "./services/account";
import { usingEmulators } from "./services/firebase";
import { SignIn } from "./screens/SignIn";
import { StudentHome } from "./screens/StudentHome";
import { LessonsScreen } from "./screens/LessonsScreen";
import { BuyMinutes } from "./screens/BuyMinutes";
import { ProfileScreen } from "./screens/ProfileScreen";
import { HelpScreen } from "./screens/HelpScreen";
import { TeacherHome } from "./screens/TeacherHome";
import { TeacherEarnings, TeacherLessons } from "./screens/TeacherEarnings";
import { TeacherSubjects } from "./screens/TeacherSubjects";
import { LegalLink, LegalProvider } from "./screens/LegalViewer";
import { CompleteProfile } from "./screens/CompleteProfile";
import { EmailBanner } from "./screens/EmailBanner";
import { Notices } from "./screens/Notices";
import { CreateAccountPrompt } from "./screens/CreateAccount";
import { takePaymentReturn } from "./services/purchase";

// The payment pages send their tab back here when they finish. The tab that
// started the purchase follows the checkout itself, so this one only says how
// it ended and closes.
const paymentReturn = takePaymentReturn();
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
  // The revision changes when the same user changes in place (an email linked
  // to an anonymous account, an address verified), so everything re-reads it.
  const [auth, setAuth] = useState<{ user: User | null; revision: number } | undefined>(undefined);
  const user = auth?.user;
  // undefined while loading; null when the account has no profile document.
  const [profile, setProfile] = useState<StudentProfile | null | undefined>(undefined);
  const [checkingRole, setCheckingRole] = useState(false);
  useEffect(() => watchRoleCheck(setCheckingRole), []);

  useEffect(() => watchAuth((u, revision) => setAuth({ user: u, revision })), []);
  const uid = user?.uid;
  const [profileFailed, setProfileFailed] = useState(false);
  useEffect(() => {
    setProfile(undefined);
    setProfileFailed(false);
    if (!uid) return;
    return watchProfile(uid, setProfile, () => setProfileFailed(true));
  }, [uid]);

  // An anonymous student whose profile was lost is written again
  // (UserService.resumeRoute).
  useEffect(() => {
    if (user?.isAnonymous && profile === null) void saveAnonymousStudentProfile(user.uid).catch((e) => console.error("[app] anonymous profile", e));
  }, [user, profile]);

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
  // Log Out asks first, as the apps' settings do (SettingsConfirmation.logOut).
  const [confirmingSignOut, setConfirmingSignOut] = useState(false);
  const [returned, setReturned] = useState(paymentReturn);

  const wrap = (body: React.ReactNode) => (
    <LanguageContext.Provider value={ctx}>
      <LegalProvider>
        {usingEmulators && <div className="dev-banner">{t.devBanner}</div>}
        {body}
        <Notices />
        {confirmingSignOut && (
          <div className="scrim" onClick={() => setConfirmingSignOut(false)}>
            <div className="dialog" role="alertdialog" aria-modal="true" aria-label={t.signOut} onClick={(e) => e.stopPropagation()}>
              <h3>{t.signOut}</h3>
              <p className="muted">{t.logOutConfirm}</p>
              <div className="dialog-actions">
                <button className="secondary" autoFocus onClick={() => setConfirmingSignOut(false)}>
                  {t.cancel}
                </button>
                <button
                  className="danger-button"
                  onClick={() => {
                    setConfirmingSignOut(false);
                    void signOut();
                  }}
                >
                  {t.signOut}
                </button>
              </div>
            </div>
          </div>
        )}
      </LegalProvider>
    </LanguageContext.Provider>
  );

  if (returned) return wrap(<PaymentReturn status={returned.status} onBack={() => setReturned(null)} />);
  if (auth === undefined) return null;

  /** A screen of its own before the dashboard: signing in and onboarding. */
  const single = (heading: string, sub: string, body: React.ReactNode, signedIn: boolean) =>
    wrap(
      <div className="narrow onboarding">
        <header className="top">
          <div>
            <h1>{heading}</h1>
            <p className="muted">{sub}</p>
          </div>
          <div className="top-actions">
            <button className="link" onClick={ctx.toggle}>
              {t.language}
            </button>
            {signedIn && (
              <button className="link" onClick={() => setConfirmingSignOut(true)}>
                {t.signOut}
              </button>
            )}
          </div>
        </header>
        <main>{body}</main>
        <footer className="legal-foot">
          <LegalLink page="eula">{t.termsOfService}</LegalLink>
          <LegalLink page="privacy">{t.privacyPolicy}</LegalLink>
        </footer>
      </div>,
    );

  if (!user || checkingRole) return single(t.appName, t.tagline, <SignIn />, false);

  if (profileFailed) {
    return single(
      t.appName,
      t.tagline,
      <div className="card center">
        <p>{t.loadFailed}</p>
        <button className="secondary" onClick={() => location.reload()}>
          {t.retry}
        </button>
      </div>,
      true,
    );
  }

  const { route, role } = resumeRoute(user, profile);
  if (route === "loading") return null;

  // A teacher chooses subjects first: dispatch matches questions on them
  // (UserService.resumeRoute → .teacherSubjects).
  if (route === "teacherSubjects") {
    return single(
      t.welcomeTeacher(profile?.fullName.split(" ")[0] ?? ""),
      t.welcomeTeacherBody,
      // The profile listener sees the save and moves on.
      <TeacherSubjects current={profile?.subjectSelections ?? {}} onSaved={() => {}} />,
      true,
    );
  }
  if (route === "completeProfile") {
    return single(t.appName, t.tagline, <CompleteProfile key={user.uid} role={role} user={user} profile={profile ?? null} />, true);
  }

  // Home: the profile is there and complete.
  const me = profile!;
  const isTeacher = role === "teacher";
  const anonymous = user.isAnonymous;
  const PAGES = isTeacher ? TEACHER_PAGES : STUDENT_PAGES;
  const shown: Page = PAGES.includes(page) ? page : "home";
  const label: Record<Page, string> = { home: isTeacher ? t.navTeach : t.navHome, lessons: t.navLessons, buy: t.navBuy, earnings: t.navEarnings, profile: t.navProfile, help: t.navHelp };

  return wrap(
      <div className="shell">
        <nav className="sidebar" aria-label={t.appName}>
          <div className="brand">
            <img src={`${import.meta.env.BASE_URL}icons/icon-192.png`} alt="" />
            <strong>{t.appName}</strong>
          </div>
          {isTeacher ? (
            <div className="role-chip">{t.teacherRole}</div>
          ) : (
            <button className="balance-chip" onClick={() => go("buy")} aria-label={`${t.minutesBalance}: ${me.remainingMinutes}. ${t.navBuy}`}>
              <span>{t.minutesBalance}</span>
              <strong>{me.remainingMinutes}</strong>
            </button>
          )}
          {anonymous && <div className="role-chip">{t.anonymousLabel}</div>}
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
            <button className="link" onClick={() => setConfirmingSignOut(true)}>
              {t.signOut}
            </button>
          </div>
        </nav>

        <main className="content">
          {/* Kept mounted, so a search, a lesson, or a teacher's time online carries
              on while other pages are open. */}
          {isTeacher ? (
            <div hidden={shown !== "home"}>
              <div className="banner-slot">
                <EmailBanner user={user} role="teacher" />
              </div>
              <TeacherHome key={user.uid} profile={me} />
            </div>
          ) : (
            <div hidden={shown !== "home"} className="narrow">
              {!anonymous && <EmailBanner user={user} role="student" />}
              <StudentHome profile={me} anonymous={anonymous} />
            </div>
          )}
          {shown === "lessons" && (isTeacher ? <TeacherLessons /> : <LessonsScreen />)}
          {shown === "buy" && (anonymous ? <AnonymousBuy /> : <BuyMinutes remainingMinutes={me.remainingMinutes} />)}
          {shown === "earnings" && <TeacherEarnings />}
          {shown === "profile" && (anonymous ? <AnonymousProfile /> : <ProfileScreen profile={me} />)}
          {shown === "help" && <HelpScreen profile={me} />}
        </main>

        <nav className="tabbar" aria-label={t.appName}>
          {PAGES.map((p) => (
            <button key={p} className={shown === p ? "on" : ""} aria-current={shown === p ? "page" : undefined} onClick={() => go(p)}>
              <span aria-hidden>{ICONS[p]}</span>
              {label[p]}
            </button>
          ))}
        </nav>
      </div>,
  );
}

/** The payment tab, back from the payment pages. */
function PaymentReturn({ status, onBack }: { status: "success" | "cancelled" | "no_response"; onBack: () => void }) {
  const { t } = useStrings();
  useEffect(() => {
    // A tab the app opened may close itself; one opened another way stays,
    // with the way back.
    if (status !== "no_response" && window.opener) window.close();
  }, [status]);
  return (
    <div className="narrow">
      <section className="card center payment-return">
        <h2>{t.paymentReturnTitle(status)}</h2>
        <p className="muted">{t.paymentReturnBody(status)}</p>
        <button className="primary" onClick={onBack}>
          {t.backToApp}
        </button>
      </section>
    </div>
  );
}

/** Purchases belong to an account (accountForPurchaseMessage). */
function AnonymousBuy() {
  const { t } = useStrings();
  return (
    <section className="page">
      <h2 className="page-title">{t.navBuy}</h2>
      <div className="card">
        <CreateAccountPrompt message={t.accountToBuy} />
      </div>
    </section>
  );
}

/** ProfileView for an anonymous student: no details to edit, only the way to
 *  an account. */
function AnonymousProfile() {
  const { t } = useStrings();
  return (
    <section className="page">
      <h2 className="page-title">{t.navProfile}</h2>
      <div className="card">
        <CreateAccountPrompt title={t.usingAnonymously} message={t.createAccountToKeep} />
      </div>
    </section>
  );
}

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
