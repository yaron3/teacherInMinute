import {
  createUserWithEmailAndPassword,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut as firebaseSignOut,
  type User,
} from "firebase/auth";
import { doc, getDoc, onSnapshot, setDoc, updateDoc } from "firebase/firestore";
import { auth, firestore } from "./firebase";

export interface StudentProfile {
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

export function watchAuth(onChange: (user: User | null) => void): () => void {
  return onAuthStateChanged(auth, onChange);
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

/** Thrown when the account is the other role from the one chosen. */
export class WrongRoleError extends Error {
  constructor(readonly actual: AccountRole) {
    super(`account is a ${actual}`);
  }
}

/** Signs in as `role`; an account of the other role is signed out again. */
export async function signIn(email: string, password: string, role: AccountRole = "student"): Promise<void> {
  setChecking(true);
  try {
    const { user } = await signInWithEmailAndPassword(auth, email.trim(), password);
    const actual: AccountRole = (await getDoc(doc(firestore, "users", user.uid))).data()?.role === "teacher" ? "teacher" : "student";
    if (actual !== role) {
      await firebaseSignOut(auth);
      throw new WrongRoleError(actual);
    }
  } finally {
    setChecking(false);
  }
}

/** Creates a student account with the same profile fields the mobile apps
 *  write (UserProfile.firestoreData). Minutes are server-owned: onUserCreate
 *  initialises them and onStudentSignup grants the sign-up reward once the
 *  role turns to student. */
export async function signUpStudent(fullName: string, email: string, password: string): Promise<void> {
  const { user } = await createUserWithEmailAndPassword(auth, email.trim(), password);
  await setDoc(
    doc(firestore, "users", user.uid),
    {
      uid: user.uid,
      email: user.email ?? email.trim(),
      fullName: fullName.trim(),
      phoneNumber: "",
      grade: "",
      role: "student",
      createdAt: new Date().toISOString(),
      currency: "ILS",
    },
    { merge: true },
  );
}

/** Work to finish while still signed in, such as taking a teacher offline:
 *  signing out does not clear presence by itself. */
const beforeSignOut = new Set<() => Promise<void>>();
export function onBeforeSignOut(task: () => Promise<void>): () => void {
  beforeSignOut.add(task);
  return () => beforeSignOut.delete(task);
}

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

/** Creates a teacher account with the fields the teacher app's onboarding
 *  writes (CompleteProfileViewModel): a teacher needs a name and a phone.
 *  Subjects are chosen next. */
export async function signUpTeacher(fullName: string, email: string, password: string, phone: string): Promise<void> {
  const phoneNumber = normalizePhone(phone);
  if (!phoneNumber) throw new Error("invalid phone");
  const { user } = await createUserWithEmailAndPassword(auth, email.trim(), password);
  await setDoc(
    doc(firestore, "users", user.uid),
    {
      uid: user.uid,
      email: user.email ?? email.trim(),
      fullName: fullName.trim(),
      phoneNumber,
      grade: "",
      role: "teacher",
      createdAt: new Date().toISOString(),
      currency: "ILS",
    },
    { merge: true },
  );
}

export async function signOut(): Promise<void> {
  await Promise.all([...beforeSignOut].map((task) => task().catch((e) => console.error("[account] before sign-out failed", e))));
  await firebaseSignOut(auth);
}

export function watchProfile(uid: string, onChange: (profile: StudentProfile | null) => void): () => void {
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
      onChange(null);
    },
  );
}
