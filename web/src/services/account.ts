import {
  createUserWithEmailAndPassword,
  onAuthStateChanged,
  signInWithEmailAndPassword,
  signOut as firebaseSignOut,
  type User,
} from "firebase/auth";
import { doc, onSnapshot, setDoc } from "firebase/firestore";
import { auth, firestore } from "./firebase";

export interface StudentProfile {
  role: string;
  fullName: string;
  remainingMinutes: number;
}

export function watchAuth(onChange: (user: User | null) => void): () => void {
  return onAuthStateChanged(auth, onChange);
}

export async function signIn(email: string, password: string): Promise<void> {
  await signInWithEmailAndPassword(auth, email.trim(), password);
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

export async function signOut(): Promise<void> {
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
        remainingMinutes: Number(data.remainingMinutes ?? 0),
      });
    },
    (error) => {
      console.error("[account] profile listener failed", error);
      onChange(null);
    },
  );
}
