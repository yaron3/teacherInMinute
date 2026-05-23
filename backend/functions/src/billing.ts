const HALF_MINUTE_SECONDS = 30;

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
 * Rounding rule: floor to the nearest completed 30-second slot.
 * A 1m 23s lesson (83 s) rounds down to 60 s (1.0 min), NOT up to 90 s.
 */
export function calculateBilling(
  acceptedAtMs: number,
  endedAtMs: number,
  costPerMinute: number,
  commissionRate: number
): BillingResult {
  const rawSeconds = Math.max(0, Math.floor((endedAtMs - acceptedAtMs) / 1000));
  const roundedSeconds = Math.floor(rawSeconds / HALF_MINUTE_SECONDS) * HALF_MINUTE_SECONDS;
  const roundedMinutes = roundedSeconds / 60;
  const minutesToCharge = Math.max(0, Math.round(roundedMinutes * 100) / 100);
  const cost = Math.round(roundedMinutes * costPerMinute * 100) / 100;
  const teacherEarnings = Math.round(cost * commissionRate * 100) / 100;
  return { rawSeconds, roundedSeconds, roundedMinutes, minutesToCharge, cost, teacherEarnings };
}
