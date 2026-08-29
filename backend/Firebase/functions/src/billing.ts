const SECONDS_PER_MINUTE = 60;
const HALF_MINUTE_SECONDS = SECONDS_PER_MINUTE / 2;

export interface BillingResult {
  rawSeconds: number;
  roundedSeconds: number;
  roundedMinutes: number;
  minutesToCharge: number;
  cost: number;
  teacherEarnings: number;
}

/**
 * Pure billing calculation — no Firebase calls, safe to unit-test.
 *
 * Rounding rule: round the duration to a whole minute. Durations with more
 * than 30 seconds in the partial minute round up; exactly 30 seconds rounds
 * down. For example, 3m 12s becomes 3 minutes and 3m 31s becomes 4 minutes.
 */
export function calculateBilling(
  acceptedAtMs: number,
  endedAtMs: number,
  costPerMinute: number,
  commissionRate: number
): BillingResult {
  const rawSeconds = Math.max(0, Math.floor((endedAtMs - acceptedAtMs) / 1000));
  const completedMinutes = Math.floor(rawSeconds / SECONDS_PER_MINUTE);
  const remainingSeconds = rawSeconds % SECONDS_PER_MINUTE;
  const roundedMinutes = completedMinutes + (remainingSeconds > HALF_MINUTE_SECONDS ? 1 : 0);
  const roundedSeconds = roundedMinutes * SECONDS_PER_MINUTE;
  const minutesToCharge = roundedMinutes;
  const cost = Math.round(roundedMinutes * costPerMinute * 100) / 100;
  const teacherEarnings = Math.round(cost * commissionRate * 100) / 100;
  return { rawSeconds, roundedSeconds, roundedMinutes, minutesToCharge, cost, teacherEarnings };
}

/**
 * When billing for a lesson starts.
 *
 * `startedAt` is written by `startLesson`, once both parties are connected, and
 * is the intended start. `acceptedAt` is written when the teacher accepts. The
 * later of the two is used: whichever happened last is the point both sides
 * were certainly in the session, so it never bills a student for time before
 * that.
 *
 * Taking the max also keeps a lesson billable when `startLesson` was never
 * called — previously `startedAt` alone was consulted, so a missing call made
 * the billed duration zero and the lesson silently free.
 *
 * Returns `undefined` when neither timestamp is usable, which the caller treats
 * as nothing to bill.
 */
export function billingStartMillis(
  startedAtMs: number | undefined,
  acceptedAtMs: number | undefined
): number | undefined {
  const candidates = [startedAtMs, acceptedAtMs].filter(
    (value): value is number => typeof value === "number" && Number.isFinite(value) && value > 0
  );
  if (candidates.length === 0) return undefined;
  return Math.max(...candidates);
}
