/**
 * Billing calculation tests
 *
 * Student account : s1test@a.com  (password: 123456)
 * Teacher account : t1test@a.com  (password: 123456)
 *
 * These tests cover the pure math in calculateBilling — no Firebase calls needed.
 *
 * Assumptions for all test cases:
 *   costPerMinute  = $1.00  (set on the teacher's Firestore user doc)
 *   commissionRate = 0.75   (default; teacher keeps 75 % of lesson cost)
 *   studentInitialMinutes = 20.0
 *
 * Rounding rule: lesson duration is rounded to a whole minute. More than
 * 30 seconds rounds up; exactly 30 seconds rounds down.
 */

import { calculateBilling, billingStartMillis } from "../billing";

const COST_PER_MINUTE = 1.0;   // $1.00 per minute
const COMMISSION_RATE = 0.75;  // teacher keeps 75 %
const INITIAL_STUDENT_MINUTES = 20.0;

// Fixed reference epoch; only the delta matters.
const ACCEPTED_AT_MS = 1_700_000_000_000;

function runLesson(durationSeconds: number) {
  const endedAtMs = ACCEPTED_AT_MS + durationSeconds * 1000;
  const billing = calculateBilling(
    ACCEPTED_AT_MS,
    endedAtMs,
    COST_PER_MINUTE,
    COMMISSION_RATE
  );
  const studentRemainingMinutes =
    Math.round((INITIAL_STUDENT_MINUTES - billing.minutesToCharge) * 100) / 100;
  return { ...billing, studentRemainingMinutes };
}

// ─── 1 min 23 sec (83 seconds) ────────────────────────────────────────────────
describe("Lesson 1:23 (83 s) — student: s1test@a.com, teacher: t1test@a.com", () => {
  const r = runLesson(83);

  test("raw seconds captured correctly", () => {
    expect(r.rawSeconds).toBe(83);
  });

  test("duration rounds down to 60 s", () => {
    expect(r.roundedSeconds).toBe(60);
  });

  test("student is charged 1.0 minute", () => {
    expect(r.minutesToCharge).toBe(1.0);
  });

  test("student has 19.0 minutes remaining after lesson", () => {
    expect(r.studentRemainingMinutes).toBe(19.0);
  });

  test("lesson cost is $1.00", () => {
    expect(r.cost).toBe(1.0);
  });

  test("teacher earns $0.75", () => {
    expect(r.teacherEarnings).toBe(0.75);
  });
});

// ─── 3 min 46 sec (226 seconds) ──────────────────────────────────────────────
describe("Lesson 3:46 (226 s) — student: s1test@a.com, teacher: t1test@a.com", () => {
  const r = runLesson(226);

  test("raw seconds captured correctly", () => {
    expect(r.rawSeconds).toBe(226);
  });

  test("duration rounds up to 240 s", () => {
    expect(r.roundedSeconds).toBe(240);
  });

  test("student is charged 4 minutes", () => {
    expect(r.minutesToCharge).toBe(4);
  });

  test("student has 16 minutes remaining after lesson", () => {
    expect(r.studentRemainingMinutes).toBe(16);
  });

  test("lesson cost is $4.00", () => {
    expect(r.cost).toBe(4);
  });

  test("teacher earns $3.00", () => {
    expect(r.teacherEarnings).toBe(3);
  });
});

// ─── 10 min 30 sec (630 seconds) ─────────────────────────────────────────────
describe("Lesson 10:30 (630 s) — student: s1test@a.com, teacher: t1test@a.com", () => {
  const r = runLesson(630);

  test("raw seconds captured correctly", () => {
    expect(r.rawSeconds).toBe(630);
  });

  test("duration rounds down to 600 s because exactly half does not round up", () => {
    expect(r.roundedSeconds).toBe(600);
  });

  test("student is charged 10 minutes", () => {
    expect(r.minutesToCharge).toBe(10);
  });

  test("student has 10 minutes remaining after lesson", () => {
    expect(r.studentRemainingMinutes).toBe(10);
  });

  test("lesson cost is $10.00", () => {
    expect(r.cost).toBe(10);
  });

  test("teacher earns $7.50", () => {
    expect(r.teacherEarnings).toBe(7.5);
  });
});

// ─── Edge cases ───────────────────────────────────────────────────────────────
describe("Edge cases", () => {
  test("lesson shorter than 30 s is billed 0 minutes (no charge)", () => {
    const r = runLesson(25);
    expect(r.minutesToCharge).toBe(0);
    expect(r.cost).toBe(0);
    expect(r.teacherEarnings).toBe(0);
    expect(r.studentRemainingMinutes).toBe(INITIAL_STUDENT_MINUTES);
  });

  test("exactly 30 s rounds down to 0 minutes", () => {
    const r = runLesson(30);
    expect(r.minutesToCharge).toBe(0);
    expect(r.cost).toBe(0);
  });

  test("31 s rounds up to 1 minute", () => {
    const r = runLesson(31);
    expect(r.roundedSeconds).toBe(60);
    expect(r.minutesToCharge).toBe(1);
    expect(r.studentRemainingMinutes).toBe(19);
  });

  test("3 min 12 s rounds down and deducts exactly 3 minutes", () => {
    const r = runLesson(3 * 60 + 12);
    expect(r.roundedSeconds).toBe(180);
    expect(r.minutesToCharge).toBe(3);
    expect(r.studentRemainingMinutes).toBe(17);
  });

  test("endedAt before acceptedAt yields 0 s (no negative charge)", () => {
    const billing = calculateBilling(
      ACCEPTED_AT_MS,
      ACCEPTED_AT_MS - 5000, // 5 s before accepted — shouldn't happen but guard is there
      COST_PER_MINUTE,
      COMMISSION_RATE
    );
    expect(billing.rawSeconds).toBe(0);
    expect(billing.minutesToCharge).toBe(0);
    expect(billing.cost).toBe(0);
  });
});

/**
 * Which timestamp billing starts from.
 *
 * Regression cover: `startedAt` alone used to be consulted, so a lesson where
 * `startLesson` was never called billed from `endedAt` — zero duration, zero
 * charge, and `endLesson` still reported success.
 */
describe("billingStartMillis", () => {
  const accepted = 1_700_000_000_000;
  const started = accepted + 30_000; // connected 30s after accept

  it("uses startedAt when it is the later of the two", () => {
    expect(billingStartMillis(started, accepted)).toBe(started);
  });

  it("falls back to acceptedAt when startLesson never ran", () => {
    expect(billingStartMillis(undefined, accepted)).toBe(accepted);
  });

  it("uses acceptedAt when it is somehow the later of the two", () => {
    const lateAccept = started + 5_000;
    expect(billingStartMillis(started, lateAccept)).toBe(lateAccept);
  });

  it("uses startedAt when there is no acceptedAt", () => {
    expect(billingStartMillis(started, undefined)).toBe(started);
  });

  it.each([
    ["both missing", undefined, undefined],
    ["both zero", 0, 0],
    ["not finite", NaN, undefined],
  ])("returns undefined when there is nothing usable (%s)", (_label, a, b) => {
    expect(billingStartMillis(a as number | undefined, b as number | undefined)).toBeUndefined();
  });

  it("bills a real 2 minute lesson rather than nothing", () => {
    // The reported failure: a 2 minute session that left the balance untouched.
    const endedAt = accepted + 120_000;
    const start = billingStartMillis(undefined, accepted)!;
    const billing = calculateBilling(start, endedAt, COST_PER_MINUTE, COMMISSION_RATE);
    expect(billing.minutesToCharge).toBe(2);
    expect(billing.cost).toBeCloseTo(2 * COST_PER_MINUTE, 5);
  });
});
