// ─── Admin Live page: details ────────────────────────────────────────────────
//
// What the public status page leaves out: who exactly is online — their
// account, rating, presence and when a question last reached them — and how
// many people signed up lately. Read on its own poll, slower than the status
// checks (see ./liveStatus), because it lists every account.
//
// Demo users (see ./demoUsers) are flagged, not hidden, in the teacher list,
// and left out of the sign-up counts, as on the Overview page.

import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { readDemoUserUids } from "./demoUsers";
import { ONLINE_TEACHERS_PATH } from "./presence";

const HOUR_MS = 3600_000;
const DAY_MS = 24 * HOUR_MS;

/** How far back invitations are counted. Questions record whom they invited,
 *  not teachers what they were sent, so this is a scan of recent questions. */
export const INVITE_LOOKBACK_DAYS = 7;

export interface OnlineTeacherDetail {
  uid: string;
  name: string | null;
  email: string | null;
  photoUrl: string | null;
  subjects: string[];
  demo: boolean;
  verified: boolean;
  rating: number | null;
  ratingCount: number;
  /** When they came online. */
  onlineSince: number | null;
  /** The app's latest keep-alive. */
  lastSeenAt: number | null;
  availability: string | null;
  busy: boolean;
  /** The latest question they were invited to, within INVITE_LOOKBACK_DAYS. */
  lastInvitedAt: number | null;
  /** The latest question they took, among their 20 newest — practice runs
   *  with the simulated demo student are left out. */
  lastAcceptedAt: number | null;
  invitedLastDay: number;
  invitedLastWeek: number;
  acceptedLastDay: number;
  acceptedLastWeek: number;
  joinedAt: number | null;
  totalMinutes: number;
}

export interface SignupRow {
  uid: string;
  createdAtMs: number;
  anonymous: boolean;
  role: string | null;
}

export interface SignupWindow {
  /** Accounts with an email or provider, not anonymous ones. */
  total: number;
  students: number;
  teachers: number;
  /** Accounts that have not picked a role yet. */
  noRole: number;
  /** Anonymous accounts: apps opened, nobody signed up. */
  anonymous: number;
}

export const SIGNUP_WINDOWS = { day: DAY_MS, week: 7 * DAY_MS, month: 30 * DAY_MS } as const;
export type SignupWindowName = keyof typeof SIGNUP_WINDOWS;

/** Sign-ups in the last day, week and 30 days, demo users left out. */
export function summarizeSignups(
  rows: SignupRow[],
  nowMs: number,
  demoUids: Set<string>
): Record<SignupWindowName, SignupWindow> {
  const out = {} as Record<SignupWindowName, SignupWindow>;
  for (const [name, span] of Object.entries(SIGNUP_WINDOWS) as [SignupWindowName, number][]) {
    const w: SignupWindow = { total: 0, students: 0, teachers: 0, noRole: 0, anonymous: 0 };
    for (const r of rows) {
      if (demoUids.has(r.uid) || nowMs - r.createdAtMs > span || r.createdAtMs > nowMs) continue;
      if (r.anonymous) {
        w.anonymous++;
        continue;
      }
      w.total++;
      if (r.role === "student") w.students++;
      else if (r.role === "teacher") w.teachers++;
      else w.noRole++;
    }
    out[name] = w;
  }
  return out;
}

export interface QuestionRow {
  createdAtMs: number;
  acceptedAtMs: number | null;
  acceptedBy: string | null;
  invited: string[];
}

export interface TeacherActivity {
  lastInvitedAt: number | null;
  invitedLastDay: number;
  invitedLastWeek: number;
  acceptedLastDay: number;
  acceptedLastWeek: number;
}

/** Per teacher, the invitations and acceptances among recent questions. */
export function summarizeTeacherActivity(questions: QuestionRow[], uid: string, nowMs: number): TeacherActivity {
  const a: TeacherActivity = { lastInvitedAt: null, invitedLastDay: 0, invitedLastWeek: 0, acceptedLastDay: 0, acceptedLastWeek: 0 };
  for (const q of questions) {
    // A question the teacher took reached them, whether or not its invite
    // list names them (a backfilled or sent-to-all question may not).
    if (q.invited.includes(uid) || q.acceptedBy === uid) {
      a.lastInvitedAt = Math.max(a.lastInvitedAt ?? 0, q.createdAtMs);
      if (nowMs - q.createdAtMs <= DAY_MS) a.invitedLastDay++;
      if (nowMs - q.createdAtMs <= 7 * DAY_MS) a.invitedLastWeek++;
    }
    if (q.acceptedBy === uid) {
      const at = q.acceptedAtMs ?? q.createdAtMs;
      if (nowMs - at <= DAY_MS) a.acceptedLastDay++;
      if (nowMs - at <= 7 * DAY_MS) a.acceptedLastWeek++;
    }
  }
  return a;
}

function toMs(value: unknown): number | null {
  if (!value) return null;
  if (typeof value === "number") return value;
  const obj = value as { toMillis?: () => number };
  return typeof obj.toMillis === "function" ? obj.toMillis() : null;
}

function str(value: unknown): string | null {
  return typeof value === "string" && value.trim() ? value : null;
}

function isAnonymous(user: admin.auth.UserRecord): boolean {
  return user.providerData.length === 0 && !user.email && !user.phoneNumber;
}

/** Every Auth account's creation time, page by page. */
async function listSignupAccounts(): Promise<admin.auth.UserRecord[]> {
  const users: admin.auth.UserRecord[] = [];
  let pageToken: string | undefined;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    users.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);
  return users;
}

export interface LiveDetails {
  checkedAt: number;
  teachers: OnlineTeacherDetail[];
  signups: Record<SignupWindowName, SignupWindow>;
  /** The most recent sign-ups (demo users left out), newest first. */
  recentSignups: Array<{ uid: string; email: string | null; name: string | null; role: string | null; createdAt: number }>;
  inviteLookbackDays: number;
}

export async function readLiveDetails(nowMs: number): Promise<LiveDetails> {
  const firestore = admin.firestore();
  const db = admin.database();

  const [demoUids, projectionSnap, recentQuestions, accounts] = await Promise.all([
    readDemoUserUids(),
    db.ref(ONLINE_TEACHERS_PATH).once("value"),
    // Ending a lesson copies the live question back with `createdAt` as plain
    // milliseconds rather than a Timestamp, and Firestore ranges never match
    // across types — so both are queried and merged.
    Promise.all([
      firestore.collection("questions").where("createdAt", ">=", Timestamp.fromMillis(nowMs - INVITE_LOOKBACK_DAYS * DAY_MS)).get(),
      firestore.collection("questions").where("createdAt", ">=", nowMs - INVITE_LOOKBACK_DAYS * DAY_MS).get(),
    ]).then(([stamped, numeric]) => [...new Map([...stamped.docs, ...numeric.docs].map((d) => [d.id, d])).values()]),
    listSignupAccounts(),
  ]);

  const projection = (projectionSnap.val() ?? {}) as Record<string, Record<string, unknown>>;
  const uids = Object.keys(projection);
  const authByUid = new Map(accounts.map((u) => [u.uid, u]));

  const questions: QuestionRow[] = recentQuestions.filter((d) => d.data().isDemo !== true).map((d) => {
    const q = d.data();
    return {
      createdAtMs: toMs(q.createdAt) ?? 0,
      acceptedAtMs: toMs(q.acceptedAt),
      acceptedBy: str(q.acceptedByTeacher),
      invited: Array.isArray(q.alreadyInvited) ? q.alreadyInvited.filter((u: unknown): u is string => typeof u === "string") : [],
    };
  });

  const [presenceSnaps, userSnaps, teacherSnaps, lastAccepted] = await Promise.all([
    Promise.all(uids.map((uid) => db.ref(`teachers/${uid}`).once("value"))),
    uids.length ? firestore.getAll(...uids.map((uid) => firestore.collection("users").doc(uid))) : Promise.resolve([]),
    uids.length ? firestore.getAll(...uids.map((uid) => firestore.collection("teachers").doc(uid))) : Promise.resolve([]),
    // The newest question each teacher took, by the (acceptedByTeacher,
    // createdAt desc) index — all time, not just the lookback.
    Promise.all(
      uids.map((uid) =>
        firestore.collection("questions").where("acceptedByTeacher", "==", uid).orderBy("createdAt", "desc").limit(20).get()
      )
    ),
  ]);

  const teachers: OnlineTeacherDetail[] = uids.map((uid, i) => {
    const pub = projection[uid] ?? {};
    const presence = (presenceSnaps[i].val() ?? {}) as Record<string, unknown>;
    const user = (userSnaps[i]?.data() ?? {}) as Record<string, unknown>;
    const agg = (teacherSnaps[i]?.data() ?? {}) as Record<string, unknown>;
    const auth = authByUid.get(uid);
    // Practice runs with the simulated demo student (`isDemo`) are not
    // questions a student asked, so they do not count as taken.
    const last = lastAccepted[i].docs.map((d) => d.data()).find((q) => q.isDemo !== true);
    const activity = summarizeTeacherActivity(questions, uid, nowMs);
    const rating = Number(agg.averageRate);
    return {
      uid,
      name: str(user.fullName) ?? str(pub.displayName) ?? auth?.displayName ?? null,
      email: auth?.email ?? str(user.email),
      photoUrl: str(pub.photoUrl),
      subjects: Array.isArray(pub.subjects) ? (pub.subjects as string[]) : [],
      demo: demoUids.has(uid),
      verified: !!agg.verifiedAt,
      rating: Number.isFinite(rating) && rating > 0 ? rating : null,
      ratingCount: Number(agg.ratingCount) || 0,
      onlineSince: typeof pub.since === "number" ? pub.since : null,
      lastSeenAt: typeof presence.lastSeenAt === "number" ? presence.lastSeenAt : null,
      availability: str(presence.availability),
      busy: pub.busy === true || !!presence.busy,
      ...activity,
      lastAcceptedAt: last ? toMs(last.acceptedAt) ?? toMs(last.createdAt) : null,
      joinedAt: auth?.metadata.creationTime ? Date.parse(auth.metadata.creationTime) : null,
      totalMinutes: Number(user.totalMinutes) || 0,
    };
  });
  teachers.sort((a, b) => Number(a.demo) - Number(b.demo) || (b.onlineSince ?? 0) - (a.onlineSince ?? 0));

  const signupRows: SignupRow[] = accounts
    .map((u) => ({ u, created: u.metadata.creationTime ? Date.parse(u.metadata.creationTime) : NaN }))
    .filter(({ created }) => Number.isFinite(created) && nowMs - created <= SIGNUP_WINDOWS.month)
    .map(({ u, created }) => ({ uid: u.uid, createdAtMs: created, anonymous: isAnonymous(u), role: null as string | null }));

  // Roles live on the user documents; only the month's sign-ups need reading.
  const registered = signupRows.filter((r) => !r.anonymous);
  const roleSnaps = registered.length
    ? await firestore.getAll(...registered.map((r) => firestore.collection("users").doc(r.uid)))
    : [];
  const userDocs = new Map(roleSnaps.map((s) => [s.id, (s.data() ?? {}) as Record<string, unknown>]));
  for (const r of registered) r.role = str(userDocs.get(r.uid)?.role);

  const recentSignups = registered
    .filter((r) => !demoUids.has(r.uid))
    .sort((a, b) => b.createdAtMs - a.createdAtMs)
    .slice(0, 20)
    .map((r) => ({
      uid: r.uid,
      email: authByUid.get(r.uid)?.email ?? null,
      name: str(userDocs.get(r.uid)?.fullName) ?? authByUid.get(r.uid)?.displayName ?? null,
      role: r.role,
      createdAt: r.createdAtMs,
    }));

  return {
    checkedAt: nowMs,
    teachers,
    signups: summarizeSignups(signupRows, nowMs, demoUids),
    recentSignups,
    inviteLookbackDays: INVITE_LOOKBACK_DAYS,
  };
}
