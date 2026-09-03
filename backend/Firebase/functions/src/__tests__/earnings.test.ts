// earnings.ts calls admin.firestore() at module scope (directly, and via its
// ./pricing import) purely to build the `firestore` used by the exported
// onCall handlers — summarizeCompletedQuestions itself never touches it. A
// real Firebase app is not available under `jest`, so importing the module
// needs this stub in place first; jest hoists jest.mock calls above imports.
jest.mock("firebase-admin", () => ({
  firestore: jest.fn(() => ({ collection: jest.fn() })),
}));

import { summarizeCompletedQuestions, CompletedQuestion } from "../earnings";
import type { Timestamp } from "firebase-admin/firestore";

/** A Firestore Timestamp carries more than `.toDate()`, but that is the only
 *  member `summarizeCompletedQuestions` calls. */
function fakeTimestamp(date: Date): Timestamp {
  return { toDate: () => date } as unknown as Timestamp;
}

function completedQuestion(overrides: Partial<CompletedQuestion>): CompletedQuestion {
  return {
    status: "completed",
    teacherUid: "teacher-1",
    endedAt: fakeTimestamp(new Date("2026-05-15T12:00:00Z")),
    teacherEarnings: 10,
    currencyCode: "ILS",
    durationSeconds: 300,
    ...overrides,
  } as CompletedQuestion;
}

describe("summarizeCompletedQuestions", () => {
  it("sums earnings and minutes into the month a lesson ended in", () => {
    const now = new Date("2026-05-20T00:00:00Z");
    const questions = [
      completedQuestion({ teacherEarnings: 12.5, durationSeconds: 300 }), // 5 min
      completedQuestion({ teacherEarnings: 7.5, durationSeconds: 600 }), // 10 min
    ];

    const { months, totalEarningsCents, currency } = summarizeCompletedQuestions(questions, now);

    expect(currency).toBe("ILS");
    expect(months).toHaveLength(1);
    expect(months[0].earningsCents).toBe(2000); // 12.5 + 7.5 = 20.00 ILS
    expect(months[0].minutesCount).toBe(15);
    expect(months[0].lessonCount).toBe(2);
    expect(totalEarningsCents).toBe(2000);
  });

  it("splits lessons across their own calendar months", () => {
    const now = new Date("2026-06-01T00:00:00Z");
    const questions = [
      completedQuestion({ teacherEarnings: 5, endedAt: fakeTimestamp(new Date("2026-05-15T00:00:00Z")) }),
      completedQuestion({ teacherEarnings: 8, endedAt: fakeTimestamp(new Date("2026-06-01T00:00:00Z")) }),
    ];

    const { months } = summarizeCompletedQuestions(questions, now);

    expect(months.map((m) => m.id)).toEqual(["2026-05", "2026-06"]);
    expect(months[0].earningsCents).toBe(500);
    expect(months[1].earningsCents).toBe(800);
  });

  it("flags the bucket matching today's UTC month as current", () => {
    const now = new Date("2026-05-20T00:00:00Z");
    const { months } = summarizeCompletedQuestions([completedQuestion({})], now);

    expect(months[0].isCurrentMonth).toBe(true);
  });

  it("skips a question that never ended, even with earnings already on it", () => {
    // A lesson mid-flight: teacherEarnings can legitimately be unset here, but
    // any stray value must not be counted before endedAt actually lands.
    const now = new Date("2026-05-20T00:00:00Z");
    const { months, totalEarningsCents } = summarizeCompletedQuestions(
      [completedQuestion({ endedAt: undefined, status: "in_progress" })],
      now
    );

    expect(months).toHaveLength(0);
    expect(totalEarningsCents).toBe(0);
  });

  it("skips a question with an end time but a status other than completed", () => {
    // Regression guard: this is what a cancelled question with a stray
    // endedAt would look like — it must not be counted as a paid lesson.
    const now = new Date("2026-05-20T00:00:00Z");
    const { months } = summarizeCompletedQuestions([completedQuestion({ status: "cancelled" })], now);

    expect(months).toHaveLength(0);
  });

  it("reads durationSeconds, not the lessons-collection-only billedSeconds field", () => {
    // Regression guard for the bug this file fixes: earnings previously read
    // `billedSeconds`, a field that is never written onto a `questions` doc,
    // so every lesson's minutes silently summed to zero.
    const now = new Date("2026-05-20T00:00:00Z");
    const question = completedQuestion({ durationSeconds: 125 }); // rounds to 2 min
    (question as unknown as Record<string, unknown>).billedSeconds = 99999;

    const { months } = summarizeCompletedQuestions([question], now);

    expect(months[0].minutesCount).toBe(2);
  });

  it("rounds a zero-second lesson up to a minimum of one billed minute", () => {
    const now = new Date("2026-05-20T00:00:00Z");
    const { months } = summarizeCompletedQuestions([completedQuestion({ durationSeconds: 10 })], now);

    expect(months[0].minutesCount).toBe(1);
  });

  it("takes the currency from the first question that has one", () => {
    const now = new Date("2026-05-20T00:00:00Z");
    const questions = [
      completedQuestion({ currencyCode: undefined }),
      completedQuestion({ currencyCode: "usd" }),
    ];

    const { currency } = summarizeCompletedQuestions(questions, now);

    expect(currency).toBe("USD");
  });

  it("returns nothing for a teacher with no completed lessons", () => {
    const { months, totalEarningsCents, currency } = summarizeCompletedQuestions([], new Date());

    expect(months).toHaveLength(0);
    expect(totalEarningsCents).toBe(0);
    expect(currency).toBe("");
  });
});
