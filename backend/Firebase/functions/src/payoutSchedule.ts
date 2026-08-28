// ─── Teacher payout schedule ─────────────────────────────────────────────────
//
// A month's earnings are paid on the 9th of the *following* month — March's
// earnings are paid on 9 April. So the pending payout is the 9th of this month
// (covering last month) until the 9th has passed, and the 9th of next month
// (covering this month, still accruing) from then on.
//
// Pure date math, kept free of firebase-admin so it can be unit tested.

/** Day of the month a payout is made for the preceding month's earnings. */
export const PAYOUT_DAY_OF_MONTH = 9;

export interface NextPayout {
  /** Calendar year of the earnings period being paid. */
  periodYear: number;
  /** Calendar month (1-12) of the earnings period being paid. */
  periodMonth: number;
  /** "yyyy-MM" key of that earnings period. */
  periodMonthId: string;
  /** Payout date as "yyyy-MM-dd". */
  payoutDate: string;
}

export function monthKey(year: number, month: number): string {
  return `${String(year).padStart(4, "0")}-${String(month).padStart(2, "0")}`;
}

export function nextPayoutFor(now: Date): NextPayout {
  const year = now.getUTCFullYear();
  const month = now.getUTCMonth() + 1; // 1-12

  // Before the 9th, this month's payout has not happened yet and it covers
  // last month; on or after the 9th it has, so the next one covers this month.
  const beforePayoutDay = now.getUTCDate() < PAYOUT_DAY_OF_MONTH;
  const periodMonth = beforePayoutDay ? (month === 1 ? 12 : month - 1) : month;
  const periodYear = beforePayoutDay && month === 1 ? year - 1 : year;

  // Paid the month after the period it covers.
  const payoutMonth = periodMonth === 12 ? 1 : periodMonth + 1;
  const payoutYear = periodMonth === 12 ? periodYear + 1 : periodYear;

  return {
    periodYear,
    periodMonth,
    periodMonthId: monthKey(periodYear, periodMonth),
    payoutDate: `${monthKey(payoutYear, payoutMonth)}-${String(PAYOUT_DAY_OF_MONTH).padStart(2, "0")}`,
  };
}
