import { MIN_BILLABLE_SECONDS } from "./types";

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
 * The whole minutes a lesson of `seconds` is charged.
 *
 * Under half a minute is free. From there each minute's band runs from half
 * past the minute before to half past this one:
 *
 *   0:00 – 0:29   free
 *   0:30 – 1:30   1 minute
 *   1:31 – 2:30   2 minutes
 *   2:31 – 3:30   3 minutes, and so on.
 *
 * Past the first minute, a partial minute of more than 30 seconds counts as a
 * whole one and 30 seconds or less does not; the first minute is charged from
 * 30 seconds exactly.
 */
export function billedMinutes(seconds: number): number {
  if (seconds < MIN_BILLABLE_SECONDS) return 0;
  const completedMinutes = Math.floor(seconds / SECONDS_PER_MINUTE);
  const remainingSeconds = seconds % SECONDS_PER_MINUTE;
  return Math.max(1, completedMinutes + (remainingSeconds > HALF_MINUTE_SECONDS ? 1 : 0));
}

/**
 * Pure billing calculation — no Firebase calls, safe to unit-test.
 *
 * The lesson's time is counted to the second, from `acceptedAtMs` (by now the
 * lesson's start: both sides connected — see billingStartMillis) to
 * `endedAtMs`, and charged in whole minutes by `billedMinutes`. For example,
 * 3m 12s is charged 3 minutes and 3m 31s is charged 4.
 */
export function calculateBilling(
  acceptedAtMs: number,
  endedAtMs: number,
  costPerMinute: number,
  commissionRate: number
): BillingResult {
  const rawSeconds = Math.max(0, Math.floor((endedAtMs - acceptedAtMs) / 1000));
  const roundedMinutes = billedMinutes(rawSeconds);
  const roundedSeconds = roundedMinutes * SECONDS_PER_MINUTE;
  const minutesToCharge = roundedMinutes;
  const cost = Math.round(roundedMinutes * costPerMinute * 100) / 100;
  const teacherEarnings = Math.round(cost * commissionRate * 100) / 100;
  return { rawSeconds, roundedSeconds, roundedMinutes, minutesToCharge, cost, teacherEarnings };
}

/**
 * When billing for a lesson starts.
 *
 * `startedAt` is written by `startLesson`, once both parties are connected: it
 * is the lesson's start, and the moment both apps count its time from. A lesson
 * is billed from the same moment, so the time either side sees is the time it
 * pays or is paid for.
 *
 * `acceptedAt`, written when the teacher accepts, stands in only when there is
 * no start at all — a lesson from before `startLesson` existed — so that one is
 * still billed rather than silently free. It is never preferred over a start:
 * acceptance comes first, so a later `acceptedAt` can only be a phone's clock.
 *
 * Returns `undefined` when neither timestamp is usable, which the caller treats
 * as nothing to bill.
 */
export function billingStartMillis(
  startedAtMs: number | undefined,
  acceptedAtMs: number | undefined
): number | undefined {
  return [startedAtMs, acceptedAtMs].find(
    (value): value is number => typeof value === "number" && Number.isFinite(value) && value > 0
  );
}

export interface TeacherBonusSplit {
  /** What the teacher is paid for the lesson, in major units. */
  teacherEarnings: number;
  /** Bonus minutes this lesson used up. */
  bonusMinutesUsed: number;
  /** `teacherEarnings / cost`, for display; the base share when cost is 0. */
  effectiveShare: number;
}

/**
 * Teacher earnings when part of the lesson falls inside a welcome bonus (see
 * ./emailRewards). The first `bonusMinutesAvailable` billed minutes earn
 * `bonusShare`; any minutes past that earn `baseShare`. Cost is split by
 * minutes, so a lesson wholly inside the bonus pays `cost × bonusShare` and one
 * with no bonus matches `calculateBilling` exactly.
 */
export function applyTeacherBonus(
  cost: number,
  billedMinutes: number,
  baseShare: number,
  bonusShare: number,
  bonusMinutesAvailable: number
): TeacherBonusSplit {
  const minutes = Math.max(0, Math.floor(billedMinutes));
  const bonusMinutesUsed = Math.min(minutes, Math.max(0, Math.floor(bonusMinutesAvailable)));
  // A lesson that cost nothing earns nothing either way, so it keeps the bonus.
  if (bonusMinutesUsed === 0 || cost <= 0) {
    return {
      teacherEarnings: Math.round(Math.max(0, cost) * baseShare * 100) / 100,
      bonusMinutesUsed: 0,
      effectiveShare: baseShare,
    };
  }
  const bonusCost = (cost * bonusMinutesUsed) / minutes;
  const earnings = bonusCost * bonusShare + (cost - bonusCost) * baseShare;
  const teacherEarnings = Math.round(earnings * 100) / 100;
  return {
    teacherEarnings,
    bonusMinutesUsed,
    effectiveShare: Math.round((teacherEarnings / cost) * 10_000) / 10_000,
  };
}
