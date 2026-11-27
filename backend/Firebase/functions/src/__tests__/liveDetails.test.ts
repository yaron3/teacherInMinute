/**
 * The admin Live page's sign-up counts and per-teacher invitation figures.
 */

jest.mock("firebase-admin", () => ({}));
jest.mock("../presence", () => ({ ONLINE_TEACHERS_PATH: "onlineTeachers" }));
jest.mock("../demoUsers", () => ({ readDemoUserUids: async () => new Set() }));

import { summarizeSignups, summarizeTeacherActivity, SignupRow, QuestionRow } from "../liveDetails";

const HOUR = 3600_000;
const DAY = 24 * HOUR;
const NOW = Date.UTC(2026, 10, 27, 12);

describe("summarizeSignups", () => {
  const row = (p: Partial<SignupRow>): SignupRow => ({ uid: "u", createdAtMs: NOW - HOUR, anonymous: false, role: "student", ...p });

  it("counts sign-ups per rolling window by role, anonymous accounts apart", () => {
    const s = summarizeSignups([
      row({ uid: "a" }),
      row({ uid: "b", role: "teacher", createdAtMs: NOW - 3 * DAY }),
      row({ uid: "c", role: null, createdAtMs: NOW - 20 * DAY }),
      row({ uid: "d", anonymous: true, role: null }),
      row({ uid: "e", createdAtMs: NOW - 40 * DAY }),
    ], NOW, new Set());
    expect(s.day).toEqual({ total: 1, students: 1, teachers: 0, noRole: 0, anonymous: 1 });
    expect(s.week).toEqual({ total: 2, students: 1, teachers: 1, noRole: 0, anonymous: 1 });
    expect(s.month).toEqual({ total: 3, students: 1, teachers: 1, noRole: 1, anonymous: 1 });
  });

  it("leaves demo users out", () => {
    expect(summarizeSignups([row({ uid: "demo" })], NOW, new Set(["demo"])).day.total).toBe(0);
  });
});

describe("summarizeTeacherActivity", () => {
  const q = (p: Partial<QuestionRow>): QuestionRow => ({ createdAtMs: NOW - HOUR, acceptedAtMs: null, acceptedBy: null, invited: [], ...p });

  it("finds the latest invitation and counts invitations and acceptances per window", () => {
    const a = summarizeTeacherActivity([
      q({ invited: ["t", "x"], createdAtMs: NOW - 2 * HOUR, acceptedBy: "t", acceptedAtMs: NOW - 2 * HOUR + 30_000 }),
      q({ invited: ["t"], createdAtMs: NOW - 3 * DAY }),
      q({ invited: ["x"], createdAtMs: NOW - HOUR }),
    ], "t", NOW);
    expect(a).toEqual({ lastInvitedAt: NOW - 2 * HOUR, invitedLastDay: 1, invitedLastWeek: 2, acceptedLastDay: 1, acceptedLastWeek: 1 });
  });

  it("counts a question the teacher took as sent to them, even when its invite list leaves them out", () => {
    const a = summarizeTeacherActivity([q({ acceptedBy: "t", createdAtMs: NOW - HOUR, acceptedAtMs: NOW - HOUR })], "t", NOW);
    expect([a.lastInvitedAt, a.invitedLastDay, a.acceptedLastDay]).toEqual([NOW - HOUR, 1, 1]);
  });

  it("reports no invitation for a teacher nobody invited", () => {
    expect(summarizeTeacherActivity([q({ invited: ["x"] })], "t", NOW).lastInvitedAt).toBeNull();
  });
});
