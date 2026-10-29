/**
 * The daily summary email: recipient parsing, formatting, and the teacher
 * availability it reads from the hourly presence history.
 */

import { resetFakeFirebase } from "./support/fakeFirebase";

jest.mock("firebase-admin", () => {
  const fake = require("./support/fakeFirebase");
  return { database: () => fake.fakeRtdb, firestore: () => fake.fakeFirestore };
});

import { DailyReport, formatDailyReportEmail, formatMinutes, parseRecipients } from "../dailyReport";
import { recordOnlineTeacherSample, summarizeTeacherAvailability } from "../presenceHistory";

const HOUR = 60 * 60_000;
const DAY = 24 * HOUR;
const NINE = Date.UTC(2026, 9, 25, 6, 0, 0); // 09:00 in Israel

beforeEach(() => resetFakeFirebase(NINE));

describe("parseRecipients", () => {
  test("splits on commas and newlines, lowercases and dedupes", () => {
    expect(parseRecipients("A@x.com, b@y.com\na@x.com\n\n")).toEqual(["a@x.com", "b@y.com"]);
  });

  test("accepts a list", () => {
    expect(parseRecipients([" a@x.com ", ""])).toEqual(["a@x.com"]);
  });
});

describe("formatMinutes", () => {
  test.each([
    [null, "—"],
    [42, "42s"],
    [125, "2m 5s"],
    [3 * 3600 + 20 * 60, "3h 20m"],
  ])("%p → %p", (seconds, expected) => {
    expect(formatMinutes(seconds)).toBe(expected);
  });
});

describe("formatDailyReportEmail", () => {
  const report: DailyReport = {
    fromMs: NINE - DAY,
    toMs: NINE,
    users: { created: 7, teachers: 2, students: 4, noRole: 1, registered: 3 },
    lessons: { count: 4, avgSeconds: 330 },
    teachers: { distinctTeachers: 2, onlineMinutes: 180, avgSecondsPerTeacher: 5400, hoursCovered: 24 },
    questions: { all: 9, real: 6 },
  };

  test("lists every figure", () => {
    const { subject, text } = formatDailyReportEmail(report);
    expect(subject).toContain("Daily summary");
    expect(text).toContain("New users: 7");
    expect(text).toContain("of them teachers: 2");
    expect(text).toContain("of them students: 4");
    expect(text).toContain("of them no role yet: 1");
    expect(text).toContain("Finished registration (added email): 3");
    expect(text).toContain("Sessions: 4");
    expect(text).toContain("Average session length: 5m 30s");
    expect(text).toContain("Teachers available: 2");
    expect(text).toContain("Average time available per teacher: 1h 30m");
    expect(text).toContain("Questions asked (excluding demo): 6");
    expect(text).toContain("Questions asked (including demo): 9");
    expect(text).not.toContain("of 24 hours");
  });

  test("leaves out the no-role line when every new user has a role", () => {
    const { text } = formatDailyReportEmail({ ...report, users: { ...report.users, students: 5, noRole: 0 } });
    expect(text).not.toContain("no role yet");
  });

  test("says when the presence history is short", () => {
    const { text } = formatDailyReportEmail({ ...report, teachers: { ...report.teachers, hoursCovered: 5 } });
    expect(text).toContain("covers 5 of 24 hours");
  });
});

describe("summarizeTeacherAvailability", () => {
  test("counts distinct teachers and averages their minutes online", async () => {
    await recordOnlineTeacherSample(["anna", "ben"], NINE - 3 * HOUR);
    await recordOnlineTeacherSample(["anna"], NINE - 3 * HOUR + 60_000);
    await recordOnlineTeacherSample(["carl"], NINE - 2 * DAY); // before the window
    await recordOnlineTeacherSample(["dina"], NINE + 60_000); // the hour being run in

    const summary = await summarizeTeacherAvailability(NINE - DAY, NINE);
    expect(summary).toEqual({
      distinctTeachers: 2,
      onlineMinutes: 3,
      avgSecondsPerTeacher: 90,
      hoursCovered: 1,
    });
  });
});
