// ─── How often a student may start a lesson ──────────────────────────────────
//
// Sessions are allowanced — a couple a minute, a handful an hour.
//
// Only a question a teacher accepted counts. Asking is free: a question nobody
// answers costs the student nothing, because they got nothing for it. The entry
// is stamped with when the question was *sent* rather than when it was picked
// up, so the window measures the thing the student can actually observe.
//
// The allowance behaves like tokens rather than a counter that resets on the
// clock: each session spends one, and that one comes back exactly a window
// later. Two sessions begun at 10:00:30 leave the student clear again at
// 10:01:30, not at 11:00.
//
// Known consequence of counting only accepted questions: nothing here caps how
// many *unanswered* questions a student can send, and each one still fans out
// to as many as eighteen teachers and holds each of them for the wave timeout.
// That was a deliberate choice — an unanswered question must not cost the
// student an allowance — so any ceiling on fan-out has to come from elsewhere.
//
// The record lives in `rateLimits/{uid}`, which no security rule grants anyone
// — the catch-all in firestore.rules denies what it does not name. It
// deliberately does not live on `users/{uid}`: that document is writable by the
// user it describes, so the person being limited could clear their own history.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

const firestore = admin.firestore();

/** Where the timestamps live. Server-only by virtue of being unnamed in
 *  firestore.rules. */
export const RATE_LIMIT_COLLECTION = "rateLimits";

const MINUTE_MS = 60_000;
const HOUR_MS = 3_600_000;

export interface RateLimitDecision {
  allowed: boolean;
  /** Which allowance ran out; absent when the question is allowed. */
  scope?: "minute" | "hour";
  /** Whole seconds until the oldest question ages out of that window, so the
   *  app can say when rather than just no. At least 1 when refused. */
  retryAfterSeconds?: number;
  /** The timestamps worth keeping — everything inside the hour, plus this
   *  question when it was allowed. */
  kept: number[];
}

/** Timestamps from the stored document, cleaned of anything unusable and of
 *  everything older than the longest window. */
function recentTimestamps(raw: unknown, now: number): number[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value) && value > now - HOUR_MS && value <= now)
    .sort((a, b) => a - b);
}

/**
 * Decides whether one more question fits within the allowances.
 *
 * Pure, so the arithmetic can be tested without Firestore: the caller supplies
 * the stored timestamps and gets back both the decision and what to store.
 */
export function evaluateQuestionRate(
  stored: unknown,
  now: number,
  perMinute: number,
  perHour: number
): RateLimitDecision {
  const kept = recentTimestamps(stored, now);

  const inLastMinute = kept.filter((at) => at > now - MINUTE_MS);
  const inLastHour = kept;

  // The hour is checked first: when both are exhausted, the longer wait is the
  // honest one to report.
  if (perHour > 0 && inLastHour.length >= perHour) {
    const oldest = inLastHour[inLastHour.length - perHour];
    return {
      allowed: false,
      scope: "hour",
      retryAfterSeconds: Math.max(1, Math.ceil((oldest + HOUR_MS - now) / 1000)),
      kept,
    };
  }

  if (perMinute > 0 && inLastMinute.length >= perMinute) {
    const oldest = inLastMinute[inLastMinute.length - perMinute];
    return {
      allowed: false,
      scope: "minute",
      retryAfterSeconds: Math.max(1, Math.ceil((oldest + MINUTE_MS - now) / 1000)),
      kept,
    };
  }

  return { allowed: true, kept: [...kept, now] };
}

/**
 * Prunes to the last hour and adds one session, oldest first.
 *
 * Pure, so the bookkeeping can be tested without Firestore.
 */
export function appendSession(stored: unknown, askedAt: number, now: number): number[] {
  const kept = recentTimestamps(stored, now);
  if (kept.includes(askedAt)) return kept;
  return [...kept, askedAt].sort((a, b) => a - b);
}

/**
 * Whether this student may start another session, without spending anything.
 *
 * Read-only on purpose: asking is free, and the allowance is spent only once a
 * teacher accepts (see recordSessionStart). A student whose questions all go
 * unanswered is never refused by this.
 *
 * A failure allows the question: a limiter that cannot read its own bookkeeping
 * should slow nobody down, and one extra session costs far less than refusing a
 * paying student.
 */
export async function checkQuestionAllowance(
  uid: string,
  perMinute: number,
  perHour: number,
  now: number = Date.now()
): Promise<RateLimitDecision> {
  try {
    const snap = await firestore.collection(RATE_LIMIT_COLLECTION).doc(uid).get();
    return evaluateQuestionRate(snap.data()?.sessionsAt, now, perMinute, perHour);
  } catch (error) {
    logger.error(`[rateLimit] failed reading the allowance for uid=${uid}`, error);
    return { allowed: true, kept: [] };
  }
}

/**
 * Spends one allowance, because a teacher just took this student's question.
 *
 * `askedAt` is when the question was sent, not when it was accepted: a question
 * that waited a minute for a teacher should not push the student's next ask a
 * minute further out.
 *
 * In a transaction because two teachers can accept two of the same student's
 * questions at once. Best-effort for the caller: the accept has already
 * happened, and losing one entry is not worth failing a lesson over.
 */
export async function recordSessionStart(
  uid: string,
  askedAt: number,
  now: number = Date.now()
): Promise<void> {
  const ref = firestore.collection(RATE_LIMIT_COLLECTION).doc(uid);

  await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const sessionsAt = appendSession(snap.data()?.sessionsAt, askedAt, now);
    tx.set(ref, { sessionsAt, updatedAt: now }, { merge: true });
  });

  logger.info(`[rateLimit] session recorded uid=${uid} askedAt=${askedAt}`);
}
