/**
 * The admin console's Live page: whether the system is working right now, how
 * many teachers are online, and how many questions teachers took in the last
 * hour. Small enough to poll every half minute, unlike adminDashboardStatus,
 * which reads every question and payment.
 *
 * Demo users (see ./demoUsers) are left out of every figure, as on the
 * Overview page.
 */

import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { readDemoUserUids } from "./demoUsers";
import { ONLINE_TEACHERS_PATH } from "./presence";
import { PRESENCE_HOURLY_COLLECTION, PresenceHourBucket, hourStartOf } from "./presenceHistory";

const MINUTE_MS = 60_000;
const HOUR_MS = 60 * MINUTE_MS;

/** The keep-alive watchdog sweeps once a minute; a few missed runs is a hiccup,
 *  ten is an outage — teachers who went silent stay "online" meanwhile. */
const WATCHDOG_LATE_MS = 3 * MINUTE_MS;
const WATCHDOG_DOWN_MS = 10 * MINUTE_MS;

/** A question still `searching` this long after its search should have ended
 *  means the dispatch timeout never fired for it. */
const SEARCH_OVERDUE_MS = 2 * MINUTE_MS;

export type CheckState = "ok" | "warn" | "down";

export interface StatusCheck {
  id: "watchdog" | "queue" | "presence" | "coverage";
  label: string;
  state: CheckState;
  detail: string;
}

export interface LiveStatus {
  checkedAt: number;
  /** The worst of `checks`. */
  overall: CheckState;
  checks: StatusCheck[];
  onlineTeachers: number;
  /** Questions a teacher took (`acceptedAt`) in the last hour. */
  answeredLastHour: number;
  /** Questions asked in the last hour, for scale. */
  askedLastHour: number;
}

function toMs(value: unknown): number | null {
  const millis = (value as { toMillis?: () => number } | null)?.toMillis?.();
  return typeof millis === "number" ? millis : null;
}

function involvesDemoUser(q: Record<string, unknown>, demoUids: Set<string>): boolean {
  return demoUids.has(String(q.studentUid ?? "")) || demoUids.has(String(q.acceptedByTeacher ?? ""));
}

function minutesAgo(ms: number): string {
  const m = Math.floor(ms / MINUTE_MS);
  return m < 1 ? "under a minute ago" : m === 1 ? "1 minute ago" : `${m} minutes ago`;
}

const RANK: Record<CheckState, number> = { ok: 0, warn: 1, down: 2 };

export async function readLiveStatus(nowMs: number): Promise<LiveStatus> {
  const firestore = admin.firestore();
  const db = admin.database();
  const hourAgo = Timestamp.fromMillis(nowMs - HOUR_MS);
  const thisHour = hourStartOf(nowMs);

  const [demoUids, presenceSnap, projectionSnap, searchingSnap, answeredSnap, askedSnap, bucketSnaps] =
    await Promise.all([
      readDemoUserUids(),
      // The indexed query keepAlive uses: `teachers` holds everyone who ever signed up.
      db.ref("teachers").orderByChild("status").equalTo("online").once("value"),
      db.ref(ONLINE_TEACHERS_PATH).once("value"),
      firestore.collection("questions").where("status", "==", "searching").get(),
      firestore.collection("questions").where("acceptedAt", ">=", hourAgo).get(),
      firestore.collection("questions").where("createdAt", ">=", hourAgo).get(),
      Promise.all(
        [thisHour, thisHour - HOUR_MS].map((h) =>
          firestore.collection(PRESENCE_HOURLY_COLLECTION).doc(String(h)).get()
        )
      ),
    ]);

  const checks: StatusCheck[] = [];

  // ── Keep-alive watchdog ──
  const lastSweep = Math.max(
    0,
    ...bucketSnaps.map((s) => Number((s.data() as Partial<PresenceHourBucket> | undefined)?.lastSampleMs) || 0)
  );
  const sweepAge = lastSweep > 0 ? nowMs - lastSweep : Infinity;
  checks.push({
    id: "watchdog",
    label: "Presence watchdog",
    state: sweepAge > WATCHDOG_DOWN_MS ? "down" : sweepAge > WATCHDOG_LATE_MS ? "warn" : "ok",
    detail:
      lastSweep > 0
        ? `Last sweep ${minutesAgo(sweepAge)}`
        : "No sweep recorded in the last two hours",
  });

  // ── Search queue ──
  const searching = searchingSnap.docs.map((d) => d.data()).filter((q) => !involvesDemoUser(q, demoUids));
  const overdue = searching.filter((q) => {
    const endsAt = toMs(q.searchEndsAt);
    return endsAt !== null && nowMs - endsAt > SEARCH_OVERDUE_MS;
  }).length;
  checks.push({
    id: "queue",
    label: "Search queue",
    state: overdue > 0 ? "warn" : "ok",
    detail:
      overdue > 0
        ? `${overdue} question${overdue === 1 ? "" : "s"} stuck past the search deadline`
        : `${searching.length} question${searching.length === 1 ? "" : "s"} searching`,
  });

  // ── Presence projection ──
  // A teacher online in `teachers` but missing from `onlineTeachers` is
  // invisible to students, and the reverse shows a teacher who has left.
  const presenceOnline = new Set(Object.keys((presenceSnap.val() as Record<string, unknown> | null) ?? {}));
  const published = new Set(Object.keys((projectionSnap.val() as Record<string, unknown> | null) ?? {}));
  const mismatched = [...new Set([...presenceOnline, ...published])].filter(
    (uid) => presenceOnline.has(uid) !== published.has(uid)
  ).length;
  checks.push({
    id: "presence",
    label: "Teacher presence",
    state: mismatched > 0 ? "warn" : "ok",
    detail:
      mismatched > 0
        ? `${mismatched} teacher${mismatched === 1 ? "" : "s"} out of sync — republish presence on the Overview page`
        : "In sync",
  });

  // ── Coverage ──
  const onlineTeachers = [...published].filter((uid) => !demoUids.has(uid)).length;
  checks.push({
    id: "coverage",
    label: "Teacher coverage",
    state: onlineTeachers > 0 ? "ok" : "warn",
    detail: onlineTeachers > 0 ? "Teachers available" : "No teachers online — new questions will go unanswered",
  });

  const real = (snap: typeof answeredSnap) => snap.docs.filter((d) => !involvesDemoUser(d.data(), demoUids)).length;

  return {
    checkedAt: nowMs,
    overall: checks.reduce<CheckState>((worst, c) => (RANK[c.state] > RANK[worst] ? c.state : worst), "ok"),
    checks,
    onlineTeachers,
    answeredLastHour: real(answeredSnap),
    askedLastHour: real(askedSnap),
  };
}
