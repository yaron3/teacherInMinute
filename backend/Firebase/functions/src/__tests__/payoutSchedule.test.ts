/**
 * Teacher payout schedule tests.
 *
 * Rule: a month's earnings are paid on the 9th of the following month —
 * March's earnings are paid on 9 April. Pure date math, no Firebase calls.
 */

import { nextPayoutFor, PAYOUT_DAY_OF_MONTH } from "../payoutSchedule";

const at = (iso: string) => new Date(`${iso}T12:00:00Z`);

describe("nextPayoutFor", () => {
  it("pays March earnings on 9 April", () => {
    // Late March: the 9th of March has passed, so the pending payout covers March.
    const payout = nextPayoutFor(at("2026-03-20"));
    expect(payout.periodMonthId).toBe("2026-03");
    expect(payout.payoutDate).toBe("2026-04-09");
  });

  it("still covers the previous month before the 9th", () => {
    const payout = nextPayoutFor(at("2026-04-08"));
    expect(payout.periodMonthId).toBe("2026-03");
    expect(payout.payoutDate).toBe("2026-04-09");
  });

  it("rolls to the next month's payout on the 9th itself", () => {
    const payout = nextPayoutFor(at("2026-04-09"));
    expect(payout.periodMonthId).toBe("2026-04");
    expect(payout.payoutDate).toBe("2026-05-09");
  });

  it("pays December earnings on 9 January of the next year", () => {
    const payout = nextPayoutFor(at("2026-12-15"));
    expect(payout.periodMonthId).toBe("2026-12");
    expect(payout.payoutDate).toBe("2027-01-09");
  });

  it("covers the previous December when early in January", () => {
    const payout = nextPayoutFor(at("2027-01-05"));
    expect(payout.periodMonthId).toBe("2026-12");
    expect(payout.payoutDate).toBe("2027-01-09");
  });

  it("always pays on the configured day of month", () => {
    for (const day of ["2026-01-01", "2026-06-09", "2026-11-30"]) {
      const payout = nextPayoutFor(at(day));
      expect(payout.payoutDate.endsWith(`-${String(PAYOUT_DAY_OF_MONTH).padStart(2, "0")}`)).toBe(true);
    }
  });
});
