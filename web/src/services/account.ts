import { FirebaseError } from "firebase/app";
import {
  EmailAuthProvider,
  GoogleAuthProvider,
  OAuthProvider,
  createUserWithEmailAndPassword,
  linkWithCredential,
  linkWithPopup,
  onIdTokenChanged,
  sendPasswordResetEmail,
  signInAnonymously,
  signInWithCredential,
  signInWithEmailAndPassword,
  signInWithPopup,
  signOut as firebaseSignOut,
  type AuthProvider,
  type User,
} from "firebase/auth";
import { doc, getDoc, onSnapshot, setDoc, updateDoc } from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import { auth, firestore, functions } from "./firebase";

export interface StudentProfile {
  /** "student" or "teacher"; empty until onboarding saves the profile. */
  role: string;
  fullName: string;
  email: string;
  phoneNumber: string;
  /** Canonical value, e.g. "Grade 8", "College", "Adult Learner". */
  grade: string;
  /** ISO date-time, as the apps store it; empty when never set. */
  dateOfBirth: string;
  photoUrl: string;
  remainingMinutes: number;
  /** A teacher's subjects: area → subtopic keys. Empty for a student. */
  subjectSelections: Record<string, string[]>;
}

/** The grades a student picks from (ProfileViewModel.studentGradeKeys). */
export const STUDENT_GRADES = ["Grade 8", "Grade 9", "Grade 10", "Grade 11", "Grade 12", "College", "Adult Learner"];

/** The fields a student edits, written as ProfileViewModel.persistProfileEdits
 *  does. Minutes and earnings are server-owned and never sent. */
export async function updateProfile(
  uid: string,
  fields: { fullName: string; phoneNumber: string; grade: string; dateOfBirth: string },
): Promise<void> {
  const data: Record<string, string> = {
    fullName: fields.fullName.trim(),
    phoneNumber: fields.phoneNumber.trim(),
    grade: fields.grade,
    updatedAt: new Date().toISOString(),
  };
  if (fields.dateOfBirth) data.dateOfBirth = fields.dateOfBirth;
  await updateDoc(doc(firestore, "users", uid), data);
}

// ─── Auth state ──────────────────────────────────────────────────────────────

/** Reports the signed-in user, and again whenever the same user changes in
 *  place: linking an email to an anonymous account, or a verified address
 *  after a reload. The revision tells the two apart for React. */
export function watchAuth(onChange: (user: User | null, revision: number) => void): () => void {
  let revision = 0;
  return onIdTokenChanged(auth, (user) => onChange(user, ++revision));
}

/** Makes `watchAuth` report the current user again, after a change that
 *  Firebase does not announce on its own. */
async function announceUserChange(): Promise<void> {
  await auth.currentUser?.getIdToken(true);
}

// While a sign-in checks the account's role, the app shows no dashboard, so a
// wrong choice never flashes the other side's screens.
let checkingRole = false;
const roleCheckListeners = new Set<(checking: boolean) => void>();
export function watchRoleCheck(onChange: (checking: boolean) => void): () => void {
  roleCheckListeners.add(onChange);
  onChange(checkingRole);
  return () => roleCheckListeners.delete(onChange);
}
const setChecking = (v: boolean) => {
  checkingRole = v;
  roleCheckListeners.forEach((l) => l(v));
};

export type AccountRole = "student" | "teacher";

/** The side chosen on the sign-in screen. The apps are two apps, so each knows
 *  its role (AuthRole.appRole); the web asks, and an account that has not
 *  finished onboarding, and so has no role saved, onboards as this one. */
export function chosenRole(): AccountRole {
  return localStorage.getItem("signIn.role") === "teacher" ? "teacher" : "student";
}
export function setChosenRole(role: AccountRole): void {
  localStorage.setItem("signIn.role", role);
}

/** Thrown when the account is the other role from the one chosen. */
export class WrongRoleError extends Error {
  constructor(readonly actual: AccountRole) {
    super(`account is a ${actual}`);
  }
}

/** Signs out an account whose saved role is the other side's
 *  (UserService.signOutOtherAppAccount). One without a role yet onboards as
 *  the chosen side, as on the apps. */
async function checkRole(uid: string, role: AccountRole): Promise<void> {
  const saved = (await getDoc(doc(firestore, "users", uid))).data()?.role;
  if ((saved === "student" || saved === "teacher") && saved !== role) {
    await firebaseSignOut(auth);
    throw new WrongRoleError(saved);
  }
}

// ─── Anonymous start (StudentIntroViewModel) ─────────────────────────────────

/** Lets a student in without an account, as the student app's "Get started"
 *  does: the profile says only that this is a student, and anonymous. */
export async function startAnonymously(): Promise<void> {
  setChosenRole("student");
  const { user } = await signInAnonymously(auth);
  await saveAnonymousStudentProfile(user.uid);
}

/** UserService.saveAnonymousStudentProfile. */
export async function saveAnonymousStudentProfile(uid: string): Promise<void> {
  await setDoc(
    doc(firestore, "users", uid),
    { uid, role: "student", isAnonymous: true, createdAt: new Date().toISOString(), currency: "ILS" },
    { merge: true },
  );
}

interface AnonymousSession {
  uid: string;
  idToken: string;
}

/** The anonymous session a sign-in may replace, taken before it starts
 *  (AuthService.currentAnonymousSession): afterwards its token is gone. */
async function anonymousSession(): Promise<AnonymousSession | null> {
  const user = auth.currentUser;
  if (!user?.isAnonymous) return null;
  try {
    return { uid: user.uid, idToken: await user.getIdToken() };
  } catch (e) {
    console.error("[account] anonymous token failed", e);
    return null;
  }
}

/** AuthService.finishReplacingAnonymousSession: a linked account keeps the
 *  uid and only stops calling itself anonymous, which is what earns the
 *  sign-up reward (signupRewards.ts); one replaced by signing in to another
 *  account is deleted by the backend on the strength of its token. */
async function settleAnonymousSession(session: AnonymousSession | null): Promise<void> {
  const user = auth.currentUser;
  if (!session || !user) return;
  if (user.uid === session.uid) {
    if (!user.isAnonymous) await setDoc(doc(firestore, "users", user.uid), { isAnonymous: false }, { merge: true });
    return;
  }
  httpsCallable(functions, "deleteAnonymousAccount")({ anonymousIdToken: session.idToken }).catch((e) =>
    console.error("[account] deleting the replaced anonymous account failed", e),
  );
}

// ─── Email and password ──────────────────────────────────────────────────────

/** Signs in as `role`; an account of the other role is signed out again. */
export async function signIn(email: string, password: string, role: AccountRole): Promise<void> {
  setChosenRole(role);
  setChecking(true);
  try {
    const anonymous = await anonymousSession();
    const { user } = await signInWithEmailAndPassword(auth, email.trim(), password);
    await settleAnonymousSession(anonymous);
    await checkRole(user.uid, role);
  } finally {
    setChecking(false);
  }
}

/** Creates an email account (CreateAccountViewModel.signup). A student who
 *  started anonymously has the email linked to that account instead, keeping
 *  its uid. The profile is saved by the onboarding step that follows, which
 *  is also what sets the role. */
export async function signUp(email: string, password: string, role: AccountRole): Promise<void> {
  setChosenRole(role);
  const address = email.trim();
  const current = auth.currentUser;
  if (current?.isAnonymous) {
    const anonymous = await anonymousSession();
    await linkWithCredential(current, EmailAuthProvider.credential(address, password));
    await settleAnonymousSession(anonymous);
    await announceUserChange();
  } else {
    await createUserWithEmailAndPassword(auth, address, password);
  }
  // The address and the welcome offer, for the "Your account is ready" note.
  void sendVerificationEmail(role).catch((e) => console.error("[account] verification email failed", e));
  const offer = await claimEmailReward().catch(() => null);
  publishNotice({ kind: "accountReady", email: address, role, offer });
}

/** Firebase's reset email, in the language the app is showing. */
export async function resetPassword(email: string, language: "english" | "hebrew"): Promise<void> {
  auth.languageCode = language === "hebrew" ? "he" : "en";
  await sendPasswordResetEmail(auth, email.trim());
}

// ─── Google and Apple ────────────────────────────────────────────────────────

/** Apple on the web needs a Services ID set up in Firebase, which neither
 *  project has yet; the button stays hidden until that is done. */
export const appleSignInEnabled = import.meta.env.VITE_APPLE_SIGN_IN === "true";

function providerFor(kind: "google" | "apple"): AuthProvider {
  if (kind === "google") return new GoogleAuthProvider();
  const apple = new OAuthProvider("apple.com");
  apple.addScope("email");
  apple.addScope("name");
  return apple;
}

/** Signs in or up with Google or Apple, in a popup. An anonymous student
 *  links the provider to that account; if it already belongs to another
 *  account, that one is signed in and the anonymous one deleted, as on the
 *  apps. (No redirect fallback: the site and the auth domain differ —
 *  web.app and firebaseapp.com — and browsers that partition storage lose a
 *  redirect's result between them.) */
export async function signInWithProvider(kind: "google" | "apple", role: AccountRole): Promise<void> {
  setChosenRole(role);
  const provider = providerFor(kind);
  setChecking(true);
  try {
    const anonymous = await anonymousSession();
    const current = auth.currentUser;
    try {
      if (current?.isAnonymous) await linkWithPopup(current, provider);
      else await signInWithPopup(auth, provider);
    } catch (e) {
      if (!(e instanceof FirebaseError) || e.code !== "auth/credential-already-in-use") throw e;
      const credential = kind === "google" ? GoogleAuthProvider.credentialFromError(e) : OAuthProvider.credentialFromError(e);
      if (!credential) throw e;
      await signInWithCredential(auth, credential);
    }
    await settleAnonymousSession(anonymous);
    await announceUserChange();
    if (auth.currentUser) await checkRole(auth.currentUser.uid, role);
  } finally {
    setChecking(false);
  }
}

// ─── Verification and the welcome reward ─────────────────────────────────────

/** Emails a link that verifies the account's address
 *  (functions/src/emailVerification.ts). Opened on a computer, it ends on a
 *  page that says what happened. */
export async function sendVerificationEmail(role: AccountRole): Promise<void> {
  const language = localStorage.getItem("settings.language.preference") === "hebrew" ? "he" : "en";
  await httpsCallable(functions, "sendVerificationEmail")({ language, app: role });
}

/** An email/password account whose link has not been followed yet
 *  (AuthService.hasUnverifiedEmail). Google and Apple accounts arrive verified. */
export function hasUnverifiedEmail(user: User | null): boolean {
  return !!user && !user.isAnonymous && !!user.email && !user.emailVerified;
}

/** Re-reads the account, so a link followed in another tab shows here. */
export async function refreshVerification(): Promise<void> {
  const user = auth.currentUser;
  if (!user || user.emailVerified) return;
  await user.reload();
  if (auth.currentUser?.emailVerified) await announceUserChange();
}

export interface EmailReward {
  status: "granted" | "already_granted" | "not_verified" | "claimed_by_other_account" | "not_eligible" | "unavailable" | "promotion_ended";
  role: AccountRole | null;
  studentMinutes: number;
  studentSlotsRemaining: number;
  /** A teacher's share during the bonus, as a whole percent. */
  teacherSharePercent: number;
  teacherBonusMinutes: number;
  teacherBonusMinutesRemaining: number;
  minutesAdded: number;
}

/** The welcome reward (FunctionsService.claimEmailReward): claims it when it
 *  has been earned, and otherwise says what is on offer. Idempotent; the apps
 *  call it whenever a home screen opens. */
export async function claimEmailReward(): Promise<EmailReward> {
  const { data } = await httpsCallable<unknown, Record<string, unknown>>(functions, "claimEmailReward")({});
  const num = (v: unknown) => (typeof v === "number" ? v : Number(v ?? 0)) || 0;
  return {
    status: String(data.status) as EmailReward["status"],
    role: data.role === "teacher" || data.role === "student" ? data.role : null,
    studentMinutes: num(data.studentMinutes),
    studentSlotsRemaining: num(data.studentSlotsRemaining),
    teacherSharePercent: Math.round(num(data.teacherShare) * 100),
    teacherBonusMinutes: num(data.teacherBonusMinutes),
    teacherBonusMinutesRemaining: num(data.teacherBonusMinutesRemaining),
    minutesAdded: num(data.minutesAdded),
  };
}

// ─── Notices shown over whatever screen comes next ───────────────────────────

export type Notice =
  | { kind: "accountReady"; email: string; role: AccountRole; offer: EmailReward | null }
  | { kind: "emailVerified"; minutesAdded: number };

let notice: Notice | null = null;
const noticeListeners = new Set<(n: Notice | null) => void>();
export function publishNotice(n: Notice | null): void {
  notice = n;
  noticeListeners.forEach((l) => l(n));
}
export function watchNotice(onChange: (n: Notice | null) => void): () => void {
  noticeListeners.add(onChange);
  onChange(notice);
  return () => noticeListeners.delete(onChange);
}

// ─── Onboarding (CompleteProfileViewModel) ───────────────────────────────────

/** A phone number as the profile stores it (String.normalizedProfilePhoneNumber):
 *  an Israeli one in local form ("0521234567"), any other in international form
 *  ("+15550000000"). Empty when it is neither. */
export function normalizePhone(raw: string): string {
  let kept = raw.replace(/[\s\-().]/g, "");
  let digits = kept.startsWith("+") ? kept.slice(1) : kept.startsWith("00") ? kept.slice(2) : kept;
  if (/^\d+$/.test(digits)) {
    if (digits.startsWith("972")) digits = "0" + digits.slice(3);
    if (/^0\d{8,9}$/.test(digits)) return digits;
  }
  if (kept.startsWith("00")) kept = "+" + kept.slice(2);
  return /^\+[1-9]\d{7,14}$/.test(kept) ? kept : "";
}

/** Saves the onboarding profile as UserProfile.firestoreData does. Saving the
 *  role is what finishes onboarding, and for a student what earns the sign-up
 *  reward (onStudentSignup). A teacher needs a phone; a student's is optional. */
export async function completeProfile(
  role: AccountRole,
  fields: { fullName: string; phone: string; grade: string },
): Promise<void> {
  const user = auth.currentUser;
  if (!user) throw new Error("not signed in");
  const phoneNumber = fields.phone.trim() ? normalizePhone(fields.phone) : "";
  if (fields.phone.trim() && !phoneNumber) throw new Error("invalid phone");
  if (role === "teacher" && !phoneNumber) throw new Error("phone required");
  await setDoc(
    doc(firestore, "users", user.uid),
    {
      uid: user.uid,
      email: user.email ?? "",
      fullName: fields.fullName.trim(),
      phoneNumber,
      grade: role === "student" ? fields.grade : "",
      role,
      createdAt: new Date().toISOString(),
      currency: "ILS",
    },
    { merge: true },
  );
}

/** Where a signed-in account goes (UserService.resumeRoute). */
export type Route = "loading" | "teacherSubjects" | "completeProfile" | "home";

export function resumeRoute(user: User, profile: StudentProfile | null | undefined): { route: Route; role: AccountRole } {
  // A student who started without an account has nothing to complete.
  if (user.isAnonymous) return { route: profile === undefined ? "loading" : "home", role: "student" };
  if (profile === undefined) return { route: "loading", role: chosenRole() };
  const role: AccountRole = profile?.role === "teacher" ? "teacher" : profile?.role === "student" ? "student" : chosenRole();
  // No profile or no role: onboarding has not finished, and starts over.
  const roleSaved = profile?.role === "teacher" || profile?.role === "student";
  const hasName = !!profile?.fullName.trim();
  const hasPhone = !!profile?.phoneNumber.trim();
  if (role === "teacher") {
    const hasSubjects = Object.values(profile?.subjectSelections ?? {}).some((keys) => keys.length > 0);
    if (!hasSubjects) return { route: "teacherSubjects", role };
    if (!roleSaved || !hasName || !hasPhone) return { route: "completeProfile", role };
    return { route: "home", role };
  }
  if (!roleSaved || !hasName) return { route: "completeProfile", role };
  return { route: "home", role };
}

// ─── Sign-out ────────────────────────────────────────────────────────────────

/** Work to finish while still signed in, such as taking a teacher offline:
 *  signing out does not clear presence by itself. */
const beforeSignOut = new Set<() => Promise<void>>();
export function onBeforeSignOut(task: () => Promise<void>): () => void {
  beforeSignOut.add(task);
  return () => beforeSignOut.delete(task);
}

export async function signOut(): Promise<void> {
  await Promise.all([...beforeSignOut].map((task) => task().catch((e) => console.error("[account] before sign-out failed", e))));
  await firebaseSignOut(auth);
}

/** The account's profile; null while it has no document yet. A failed read
 *  goes to `onError`, never as null: null means "onboard", and onboarding a
 *  finished account could overwrite its role. */
export function watchProfile(uid: string, onChange: (profile: StudentProfile | null) => void, onError?: (error: unknown) => void): () => void {
  return onSnapshot(
    doc(firestore, "users", uid),
    (snap) => {
      const data = snap.data();
      if (!data) return onChange(null);
      onChange({
        role: String(data.role ?? ""),
        fullName: String(data.fullName ?? ""),
        email: String(data.email ?? ""),
        phoneNumber: String(data.phoneNumber ?? ""),
        grade: String(data.grade ?? ""),
        dateOfBirth: String(data.dateOfBirth ?? ""),
        photoUrl: String(data.profileImageURL ?? data.photoURL ?? data.imageURL ?? ""),
        subjectSelections: Object.fromEntries(
          Object.entries((data.subjectSelections ?? {}) as Record<string, unknown>).map(([k, v]) => [k, Array.isArray(v) ? v.map(String) : []]),
        ),
        remainingMinutes: Number(data.remainingMinutes ?? 0),
      });
    },
    (error) => {
      console.error("[account] profile listener failed", error);
      if (onError) onError(error);
      else onChange(null);
    },
  );
}

/** The auth error as the apps word it (localizedAuthErrorMessage). */
export type AuthErrorKey = "emailInUse" | "invalidEmail" | "wrongCredentials" | "tooManyAttempts" | "network" | "weakPassword" | "popupClosed" | "popupBlocked" | "unexpected";
export function authErrorKey(error: unknown): AuthErrorKey {
  const code = error instanceof FirebaseError ? error.code : "";
  switch (code) {
    case "auth/email-already-in-use":
    case "auth/credential-already-in-use":
      return "emailInUse";
    case "auth/invalid-email":
    case "auth/missing-email":
      return "invalidEmail";
    case "auth/wrong-password":
    case "auth/user-not-found":
    case "auth/invalid-credential":
    case "auth/invalid-login-credentials":
    case "auth/user-disabled":
      return "wrongCredentials";
    case "auth/too-many-requests":
      return "tooManyAttempts";
    case "auth/network-request-failed":
      return "network";
    case "auth/weak-password":
      return "weakPassword";
    case "auth/popup-blocked":
      return "popupBlocked";
    case "auth/popup-closed-by-user":
    case "auth/cancelled-popup-request":
    case "auth/user-cancelled":
      return "popupClosed";
    default:
      return "unexpected";
  }
}
