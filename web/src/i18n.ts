import { createContext, useContext } from "react";
import type { Topic } from "./services/questions";

export type Language = "english" | "hebrew";

// Values the mobile apps publish under the same meaning. The mobile copy lives
// in Remote Config; moving the web client onto that template is a later slice.
const strings = {
  english: {
    appName: "Instant Teacher",
    tagline: "A human math teacher within 90 seconds",
    signIn: "Sign in",
    createAccount: "Create account",
    haveAccount: "Already have an account? Sign in",
    noAccount: "New here? Create an account",
    fullName: "Full name",
    email: "Email",
    password: "Password",
    signOut: "Sign out",
    minutesLeft: (n: number) => `${n} minutes left`,
    askTitle: "What are you stuck on?",
    topic: "Topic",
    questionPlaceholder: "Type your question (at least 10 characters)",
    howToTalk: "How do you want to talk?",
    text: "Chat",
    audio: "Voice",
    video: "Video",
    findTeacher: "Find a teacher",
    searching: "Looking for a teacher…",
    searchingHint: "We're asking teachers who cover this topic.",
    cancel: "Cancel",
    connecting: "Connecting…",
    waitingForTeacher: "Waiting for your teacher to connect…",
    live: "Live",
    yourTeacher: "Your teacher",
    mute: "Mute",
    unmute: "Unmute",
    endLesson: "End lesson",
    mediaFailed: "We couldn't connect audio. You can keep going by chat.",
    cameraFailed: "Your camera didn't start, so this lesson is voice only.",
    messagePlaceholder: "Write a message",
    send: "Send",
    endingLesson: "Ending the lesson…",
    lessonEnded: "The lesson has ended.",
    rateTitle: (name: string) => `How was your lesson with ${name}?`,
    lessonLength: (m: number) => `${m} min lesson`,
    ratingComment: "Anything to add? (optional)",
    submitRating: "Send rating",
    skip: "Skip",
    noTeacher: "No teacher was free this time.",
    tryAgain: "Ask again",
    done: "Back",
    cancelled: "The question was cancelled.",
    noMinutes: "You're out of minutes. Top up in the mobile app to ask.",
    rateLimited: (s: number) => `Too many questions — try again in ${s} seconds.`,
    tooLong: (n: number) => `Questions can be at most ${n} characters.`,
    genericError: "Something went wrong. Please try again.",
    language: "עברית",
    devBanner: "Local emulators",
    topics: {
      algebra: "Algebra",
      geometry: "Geometry",
      trigonometry: "Trigonometry",
      calculus: "Calculus",
      statistics: "Statistics",
      arithmetic: "Arithmetic",
    } satisfies Record<Topic, string>,
  },
  hebrew: {
    appName: "מורה לרגע",
    tagline: "מורה אנושי למתמטיקה תוך דקה וחצי",
    signIn: "התחברות",
    createAccount: "יצירת חשבון",
    haveAccount: "כבר יש לך חשבון? התחברות",
    noAccount: "חדש כאן? יצירת חשבון",
    fullName: "שם מלא",
    email: "אימייל",
    password: "סיסמה",
    signOut: "התנתקות",
    minutesLeft: (n: number) => `נותרו ${n} דקות`,
    askTitle: "במה נתקעת?",
    topic: "נושא",
    questionPlaceholder: "כתוב את השאלה שלך (לפחות 10 תווים)",
    howToTalk: "איך תרצה לדבר?",
    text: "צ׳אט",
    audio: "קול",
    video: "וידאו",
    findTeacher: "מצא מורה",
    searching: "מחפשים מורה…",
    searchingHint: "אנחנו פונים למורים שמלמדים את הנושא.",
    cancel: "ביטול",
    connecting: "מתחברים…",
    waitingForTeacher: "ממתינים שהמורה יתחבר…",
    live: "בשידור",
    yourTeacher: "המורה שלך",
    mute: "השתק",
    unmute: "בטל השתקה",
    endLesson: "סיום שיעור",
    mediaFailed: "לא הצלחנו לחבר שמע. אפשר להמשיך בצ׳אט.",
    cameraFailed: "המצלמה לא נפתחה, לכן השיעור בקול בלבד.",
    messagePlaceholder: "כתוב הודעה",
    send: "שלח",
    endingLesson: "מסיימים את השיעור…",
    lessonEnded: "השיעור הסתיים.",
    rateTitle: (name: string) => `איך היה השיעור עם ${name}?`,
    lessonLength: (m: number) => `שיעור של ${m} דק׳`,
    ratingComment: "משהו להוסיף? (לא חובה)",
    submitRating: "שלח דירוג",
    skip: "דלג",
    noTeacher: "לא נמצא מורה פנוי הפעם.",
    tryAgain: "שאל שוב",
    done: "חזרה",
    cancelled: "השאלה בוטלה.",
    noMinutes: "נגמרו לך הדקות. אפשר לטעון דקות באפליקציה.",
    rateLimited: (s: number) => `יותר מדי שאלות — נסה שוב בעוד ${s} שניות.`,
    tooLong: (n: number) => `שאלה יכולה להכיל עד ${n} תווים.`,
    genericError: "משהו השתבש. נסה שוב.",
    language: "English",
    devBanner: "אמולטורים מקומיים",
    topics: {
      algebra: "אלגברה",
      geometry: "גאומטריה",
      trigonometry: "טריגונומטריה",
      calculus: "חשבון דיפרנציאלי",
      statistics: "סטטיסטיקה",
      arithmetic: "חשבון",
    } satisfies Record<Topic, string>,
  },
};

export type Strings = (typeof strings)["english"];

export function stringsFor(language: Language): Strings {
  return strings[language];
}

export function initialLanguage(): Language {
  const saved = localStorage.getItem("settings.language.preference");
  if (saved === "english" || saved === "hebrew") return saved;
  return navigator.language.startsWith("he") ? "hebrew" : "english";
}

export const LanguageContext = createContext<{
  language: Language;
  t: Strings;
  toggle: () => void;
}>({ language: "english", t: strings.english, toggle: () => {} });

export const useStrings = () => useContext(LanguageContext);
