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
 * Rounding rule: lesson duration is floored to the nearest completed
 * 30-second slot before billing (e.g. 1m 23s → 60 s billed, not 90 s).
 */

import { calculateBilling } from "../billing";

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

  test("duration rounds down to 60 s (2 × 30-second slots)", () => {
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

  test("duration rounds down to 210 s (7 × 30-second slots)", () => {
    expect(r.roundedSeconds).toBe(210);
  });

  test("student is charged 3.5 minutes", () => {
    expect(r.minutesToCharge).toBe(3.5);
  });

  test("student has 16.5 minutes remaining after lesson", () => {
    expect(r.studentRemainingMinutes).toBe(16.5);
  });

  test("lesson cost is $3.50", () => {
    expect(r.cost).toBe(3.5);
  });

  test("teacher earns $2.63  (round($3.50 × 0.75 × 100) / 100)", () => {
    // Math.round(3.5 * 0.75 * 100) = Math.round(262.5) = 263 → $2.63
    expect(r.teacherEarnings).toBe(2.63);
  });
});

// ─── 10 min 30 sec (630 seconds) ─────────────────────────────────────────────
describe("Lesson 10:30 (630 s) — student: s1test@a.com, teacher: t1test@a.com", () => {
  const r = runLesson(630);

  test("raw seconds captured correctly", () => {
    expect(r.rawSeconds).toBe(630);
  });

  test("duration stays at 630 s (21 × 30-second slots — no remainder)", () => {
    expect(r.roundedSeconds).toBe(630);
  });

  test("student is charged 10.5 minutes", () => {
    expect(r.minutesToCharge).toBe(10.5);
  });

  test("student has 9.5 minutes remaining after lesson", () => {
    expect(r.studentRemainingMinutes).toBe(9.5);
  });

  test("lesson cost is $10.50", () => {
    expect(r.cost).toBe(10.5);
  });

  test("teacher earns $7.88  (round($10.50 × 0.75 × 100) / 100)", () => {
    // Math.round(10.5 * 0.75 * 100) = Math.round(787.5) = 788 → $7.88
    expect(r.teacherEarnings).toBe(7.88);
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

  test("exactly 30 s bills 0.5 minutes", () => {
    const r = runLesson(30);
    expect(r.minutesToCharge).toBe(0.5);
    expect(r.cost).toBe(0.5);
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
