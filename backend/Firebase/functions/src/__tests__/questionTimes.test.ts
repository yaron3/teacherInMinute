/**
 * Question times copied back from RTDB as milliseconds become Timestamps again,
 * so "since" queries find questions that ended in a lesson.
 */

import { Timestamp } from "firebase-admin/firestore";
import { questionTimeFixes, withQuestionTimestamps } from "../questionTimes";

const MS = Date.UTC(2026, 10, 24, 15, 46);

describe("questionTimeFixes", () => {
  it("turns numeric time fields into Timestamps and leaves the rest alone", () => {
    const stamp = Timestamp.fromMillis(MS);
    const fixes = questionTimeFixes({ createdAt: MS, acceptedAt: MS + 1000, startedAt: stamp, status: "completed", durationSeconds: 60 });
    expect(Object.keys(fixes).sort()).toEqual(["acceptedAt", "createdAt"]);
    expect(fixes.createdAt.toMillis()).toBe(MS);
    expect(fixes.acceptedAt.toMillis()).toBe(MS + 1000);
  });

  it("reads seconds from older writers as seconds", () => {
    expect(questionTimeFixes({ createdAt: MS / 1000 }).createdAt.toMillis()).toBe(MS);
  });

  it("skips zero and other unusable numbers", () => {
    expect(questionTimeFixes({ createdAt: 0, acceptedAt: NaN })).toEqual({});
  });
});

describe("withQuestionTimestamps", () => {
  it("keeps every other field of the copied question", () => {
    const out = withQuestionTimestamps({ createdAt: MS, text: "x", cost: 4 });
    expect(out.createdAt).toBeInstanceOf(Timestamp);
    expect(out).toMatchObject({ text: "x", cost: 4 });
  });
});
