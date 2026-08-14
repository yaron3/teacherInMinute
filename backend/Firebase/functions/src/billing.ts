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
