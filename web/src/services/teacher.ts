import { onDisconnect, onValue, ref, serverTimestamp, update, type Unsubscribe } from "firebase/database";
import { doc, getDoc } from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import { database, firestore, functions } from "./firebase";

// The teacher's side, as the apps do it.
//
// Presence lives at `teachers/{uid}` (TeacherPresenceService): `availability`
// is what the teacher asked for, `status` is whether they are in the dispatch
// pool, `subjects` the subtopic keys dispatch matches a question's topic on,
// and `lastSeenAt` a server-stamped keep-alive sent once a minute while online
// (TeacherKeepAlive). The backend takes a teacher it has not heard from in
// three minutes out of the pool (functions/src/keepAlive.ts).
//
// A web tab cannot be woken by a push, so unlike the apps it also asks the
// database to take it offline when its connection closes: a closed tab is a
// teacher nobody can reach.

const KEEP_ALIVE_MS = 60_000;

/** The presence key of a subtopic, as UserProfileSummary.rawSubjectKeys makes it. */
export const subjectKey = (raw: string) => raw.toLowerCase().replace(/[^\p{L}\p{N}]/gu, "");

export interface TeacherDetails {
  /** Subject area → its subtopic keys, as the apps store `subjectSelections`. */
  subjectSelections: Record<string, string[]>;
  subjectKeys: string[];
  verified: boolean;
}

export async function fetchTeacherDetails(uid: string): Promise<TeacherDetails> {
  const [user, record] = await Promise.all([
    getDoc(doc(firestore, "users", uid)),
    getDoc(doc(firestore, "teachers", uid)).catch(() => null),
  ]);
  const raw = (user.data()?.subjectSelections ?? {}) as Record<string, unknown>;
  const subjectSelections = Object.fromEntries(
    Object.entries(raw).map(([area, keys]) => [area, Array.isArray(keys) ? keys.map(String) : []]),
  );
  const verifiedAt = record?.data()?.verifiedAt;
  return {
    subjectSelections,
    subjectKeys: Object.values(subjectSelections).flat().map(subjectKey),
    verified: typeof verifiedAt === "string" ? verifiedAt.trim() !== "" : verifiedAt != null,
  };
}

/** Puts the teacher in the dispatch pool and keeps them there while this tab
 *  is open. The returned function takes them out again. */
export function goOnline(uid: string, subjects: string[]): () => Promise<void> {
  const teacherRef = ref(database, `teachers/${uid}`);
  const write = () =>
    update(teacherRef, { availability: "available", status: "online", subjects, lastSeenAt: serverTimestamp() });

  // Re-armed on every reconnect: onDisconnect handlers last one connection.
  const stopConnected = onValue(ref(database, ".info/connected"), (snap) => {
    if (snap.val() !== true) return;
    void onDisconnect(teacherRef).update({ status: "offline" });
    // Back after a dropped connection: online again, as the keep-alive would.
    write().catch((e) => console.error("[teacher] presence write failed", e));
  });
  const keepAlive = setInterval(() => {
    update(teacherRef, { status: "online", lastSeenAt: serverTimestamp() }).catch((e) =>
      console.error("[teacher] keep-alive failed", e),
    );
  }, KEEP_ALIVE_MS);

  return async () => {
    clearInterval(keepAlive);
    stopConnected();
    await onDisconnect(teacherRef).cancel();
    await update(teacherRef, { availability: "dnd", status: "offline" });
  };
}

/** Whether the backend has this teacher online, and in a session. */
export function watchPresence(uid: string, onChange: (p: { online: boolean; busy: boolean }) => void): Unsubscribe {
  return onValue(ref(database, `teachers/${uid}`), (snap) => {
    const d = snap.val() ?? {};
    onChange({ online: d.status === "online", busy: !!d.busy?.questionId });
  });
}

export interface Invite {
  questionId: string;
  topic: string;
  text: string;
  /** When this wave's offer runs out, epoch ms. */
  expiresAt: number;
  photoUrls: string[];
  studentName: string;
  conversationType: string;
  pricePerMinuteCents: number;
}

/** The questions offered to this teacher right now (InviteService). The
 *  backend removes an invite the moment its question is settled elsewhere. */
export function watchInvites(uid: string, onChange: (invites: Invite[]) => void): Unsubscribe {
  return onValue(ref(database, `teacherInvites/${uid}`), (snap) => {
    const invites: Invite[] = [];
    snap.forEach((child) => {
      const d = child.val();
      if (typeof d?.topic !== "string" || typeof d?.text !== "string") return;
      invites.push({
        questionId: child.key ?? "",
        topic: d.topic,
        text: d.text,
        expiresAt: Number(d.expiresAt ?? 0),
        photoUrls: Array.isArray(d.photoUrls) ? d.photoUrls.map(String) : [],
        studentName: String(d.studentName ?? d.studentFullName ?? ""),
        conversationType: String(d.conversationType ?? "text"),
        pricePerMinuteCents: Number(d.pricePerMinuteCents ?? d.ratePerMinuteCents ?? 0),
      });
    });
    invites.sort((a, b) => a.expiresAt - b.expiresAt);
    onChange(invites);
  });
}

/** Claims the question; throws if another teacher got there first. */
export async function acceptInvite(questionId: string): Promise<{ liveKitToken?: string }> {
  const result = await httpsCallable<object, { liveKitToken?: string }>(functions, "acceptInvite")({ questionId });
  return result.data;
}

export async function declineInvite(questionId: string): Promise<void> {
  await httpsCallable(functions, "declineInvite")({ questionId });
}

export interface TeacherLesson {
  questionId: string;
  endedAt: string;
  acceptedAt: string;
  lessonSeconds: number;
  earningsCents: number;
  currency: string;
  studentName: string;
  text: string;
  topic: string;
  photoUrls: string[];
  studentRating: number;
}

export interface EarningsMonth {
  id: string;
  year: number;
  month: number;
  earningsCents: number;
  minutesCount: number;
  lessonCount: number;
}

export interface EarningsSummary {
  currency: string;
  totalEarningsCents: number;
  months: EarningsMonth[];
  lessons: TeacherLesson[];
  nextPayment: { amountCents: number; payoutDate: string; periodMonthId: string } | null;
  payoutMethodSummary: string;
}

/** The teacher's lessons and earnings, worked out by the backend from the same
 *  lessons, so the two screens never disagree (teacherEarningsSummary). */
export async function fetchEarnings(): Promise<EarningsSummary> {
  const { data } = await httpsCallable<object, Partial<EarningsSummary>>(functions, "teacherEarningsSummary")({});
  return {
    currency: data.currency || "ILS",
    totalEarningsCents: data.totalEarningsCents ?? 0,
    months: data.months ?? [],
    lessons: data.lessons ?? [],
    nextPayment: data.nextPayment ?? null,
    payoutMethodSummary: data.payoutMethodSummary ?? "",
  };
}
