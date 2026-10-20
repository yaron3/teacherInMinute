// ─── Online-teacher history ──────────────────────────────────────────────────
//
// Presence is a live value: `teachers/{uid}/status` says who is online now and
// nothing about an hour ago. The admin console's "teachers online per hour"
// needs the past, so the keep-alive watchdog — which already reads every
// online teacher once a minute — folds each sweep into an hourly bucket here.
//
// One document per hour, keyed by the hour's start in epoch millis. A bucket
// holds the running sum of per-minute online counts (divide by `samples` for
// the hour's average) and the distinct teachers seen in it. Admin-only: the
// collection falls under the catch-all deny in firestore.rules.

import * as admin from "firebase-admin";

export const PRESENCE_HOURLY_COLLECTION = "teacherPresenceHourly";

const HOUR_MS = 60 * 60 * 1000;

export interface PresenceHourBucket {
  hourStartMs: number;
  /** Watchdog sweeps folded into this hour, normally 60. */
  samples: number;
  /** Sum of the online count across those sweeps. */
  onlineSum: number;
  /** Every teacher seen online at any sweep in the hour. */
  uids: string[];
}

export function hourStartOf(ms: number): number {
  return Math.floor(ms / HOUR_MS) * HOUR_MS;
}

/** Folds one sweep's online teachers into the current hour's bucket. */
export async function recordOnlineTeacherSample(onlineUids: string[], nowMs: number): Promise<void> {
  const firestore = admin.firestore();
  const hourStartMs = hourStartOf(nowMs);
  const ref = firestore.collection(PRESENCE_HOURLY_COLLECTION).doc(String(hourStartMs));

  await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = (snap.data() ?? {}) as Partial<PresenceHourBucket>;
    const uids = new Set(Array.isArray(current.uids) ? current.uids : []);
    onlineUids.forEach((uid) => uids.add(uid));

    const bucket: PresenceHourBucket = {
      hourStartMs,
      samples: (Number(current.samples) || 0) + 1,
      onlineSum: (Number(current.onlineSum) || 0) + onlineUids.length,
      uids: [...uids],
    };
    tx.set(ref, bucket);
  });
}

export interface PresenceSummary {
  /** Average number of teachers online at once, over the minutes sampled. */
  avgOnline: number | null;
  /** Average number of distinct teachers online in an hour. */
  avgDistinctPerHour: number | null;
  /** Hours with at least one sample — under 24 until a day has been recorded. */
  hoursCovered: number;
}

/** Summarises the buckets that start within `windowMs` before `nowMs`. */
export async function summarizeOnlineTeachers(nowMs: number, windowMs: number): Promise<PresenceSummary> {
  // The current, partial hour counts; the window reaches back to the hour
  // that began just inside it, so 24h covers 24 buckets.
  const fromMs = hourStartOf(nowMs) - (Math.ceil(windowMs / HOUR_MS) - 1) * HOUR_MS;
  const snap = await admin
    .firestore()
    .collection(PRESENCE_HOURLY_COLLECTION)
    .where("hourStartMs", ">=", fromMs)
    .get();

  let samples = 0;
  let onlineSum = 0;
  let distinctSum = 0;
  let hours = 0;
  for (const doc of snap.docs) {
    const b = doc.data() as Partial<PresenceHourBucket>;
    const s = Number(b.samples) || 0;
    if (s === 0) continue;
    samples += s;
    onlineSum += Number(b.onlineSum) || 0;
    distinctSum += Array.isArray(b.uids) ? b.uids.length : 0;
    hours += 1;
  }

  return {
    avgOnline: samples > 0 ? onlineSum / samples : null,
    avgDistinctPerHour: hours > 0 ? distinctSum / hours : null,
    hoursCovered: hours,
  };
}
