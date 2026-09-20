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
    const { months, totalEarningsCents, currency, lessons, firstLessonAt } =
      summarizeCompletedQuestions([], new Date());

    expect(months).toHaveLength(0);
    expect(totalEarningsCents).toBe(0);
    expect(currency).toBe("");
    expect(lessons).toHaveLength(0);
    expect(firstLessonAt).toBe("");
  });

  describe("lesson list", () => {
    it("returns exactly the lessons the totals were computed from", () => {
      const now = new Date("2026-05-20T00:00:00Z");
      const questions = [
        completedQuestion({ id: "counted", teacherEarnings: 4 }),
        // Neither of these reaches a month bucket, so neither may reach the list.
        completedQuestion({ id: "in-progress", status: "in_progress" as CompletedQuestion["status"] }),
        completedQuestion({ id: "never-ended", endedAt: undefined }),
      ];

      const { lessons, months } = summarizeCompletedQuestions(questions, now);

      expect(lessons.map((l) => l.questionId)).toEqual(["counted"]);
      expect(months[0].lessonCount).toBe(1);
      expect(lessons[0].earningsCents).toBe(400);
    });

    it("orders lessons newest first by when the teacher took them", () => {
      const now = new Date("2026-05-20T00:00:00Z");
      const questions = [
        completedQuestion({ id: "older", acceptedAt: fakeTimestamp(new Date("2026-05-10T09:00:00Z")) }),
        completedQuestion({ id: "newer", acceptedAt: fakeTimestamp(new Date("2026-05-14T09:00:00Z")) }),
      ];

      const { lessons } = summarizeCompletedQuestions(questions, now);

      expect(lessons.map((l) => l.questionId)).toEqual(["newer", "older"]);
    });

    it("reports the oldest counted lesson as the date the total runs from", () => {
      const now = new Date("2026-06-20T00:00:00Z");
      const questions = [
        completedQuestion({ endedAt: fakeTimestamp(new Date("2026-06-02T00:00:00Z")) }),
        completedQuestion({ endedAt: fakeTimestamp(new Date("2026-04-07T00:00:00Z")) }),
        completedQuestion({ endedAt: fakeTimestamp(new Date("2026-05-11T00:00:00Z")) }),
      ];

      const { firstLessonAt } = summarizeCompletedQuestions(questions, now);

      expect(firstLessonAt).toBe("2026-04-07T00:00:00.000Z");
    });

    it("reads dates and text off documents that came from the RTDB node shape", () => {
      const now = new Date("2026-05-20T00:00:00Z");
      const question = completedQuestion({
        id: undefined,
        questionId: "from-rtdb",
        endedAt: undefined,
        completedAt: "2026-05-15T12:00:00.000Z",
        acceptedAt: undefined,
        createdAt: 1779199066694 as unknown as CompletedQuestion["createdAt"],
        text: undefined,
        questionText: "  what is a derivative  ",
        studentImageURL: undefined,
        studentProfileImageURL: "https://example.com/a.png",
        cost: 9,
        studentRating: 9,
      });

      const { lessons } = summarizeCompletedQuestions([question], now);

      expect(lessons).toHaveLength(1);
      expect(lessons[0].questionId).toBe("from-rtdb");
      expect(lessons[0].endedAt).toBe("2026-05-15T12:00:00.000Z");
      expect(lessons[0].acceptedAt).toBe(new Date(1779199066694).toISOString());
      expect(lessons[0].text).toBe("what is a derivative");
      expect(lessons[0].studentImageURL).toBe("https://example.com/a.png");
      expect(lessons[0].costCents).toBe(900);
      // Ratings are 1-5; anything else is clamped rather than shown as-is.
      expect(lessons[0].studentRating).toBe(5);
    });

    it("falls back to the end date when a lesson has no start of any kind", () => {
      const now = new Date("2026-05-20T00:00:00Z");
      const question = completedQuestion({ acceptedAt: undefined, createdAt: undefined });

      const { lessons } = summarizeCompletedQuestions([question], now);

      expect(lessons[0].acceptedAt).toBe(lessons[0].endedAt);
    });
  });
});
