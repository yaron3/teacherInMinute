/**
 * The public `onlineTeachers` projection students read, run against the
 * in-memory Firebase — in particular, that it shows who is busy teaching.
 */

import { clock, fakeFirestore, fakeRtdb, resetFakeFirebase } from "./support/fakeFirebase";

jest.mock("firebase-admin", () => {
  const fake = require("./support/fakeFirebase");
  return { database: () => fake.fakeRtdb, firestore: () => fake.fakeFirestore };
});

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

jest.mock("firebase-functions/v2/database", () => ({
  onValueWritten: jest.fn((_path: string, handler: unknown) => handler),
}));

import { onTeacherPresenceBusyWritten, republishTeacherPresence } from "../presence";
import { markTeacherBusy, releaseTeacherBusy } from "../busy";

const START_MS = Date.UTC(2026, 8, 23, 9, 0, 0);
const MINUTE = 60_000;

type Trigger = (event: { params: { uid: string } }) => Promise<void>;
const busyWritten = onTeacherPresenceBusyWritten as unknown as Trigger;

function entry(uid: string): Record<string, unknown> | undefined {
  return fakeRtdb.read(`onlineTeachers/${uid}`) as Record<string, unknown> | undefined;
}

beforeEach(() => {
  resetFakeFirebase(START_MS);
  jest.spyOn(Date, "now").mockImplementation(() => clock.nowMs);
  fakeRtdb.write("teachers/teacher-anna", { status: "online", subjects: ["algebra"] });
  fakeFirestore.write("users/teacher-anna", { fullName: "Anna" }, false);
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe("busy in the public online-teacher entry", () => {
  test("a free online teacher is published as not busy", async () => {
    await republishTeacherPresence("teacher-anna");

    expect(entry("teacher-anna")).toMatchObject({
      displayName: "Anna",
      subjects: ["algebra"],
      busy: false,
    });
  });

  test("starting a session shows the teacher busy, ending it shows them free", async () => {
    await republishTeacherPresence("teacher-anna");

    await markTeacherBusy("teacher-anna", "question-1");
    await busyWritten({ params: { uid: "teacher-anna" } });
    expect(entry("teacher-anna")).toMatchObject({ busy: true });

    await releaseTeacherBusy("teacher-anna", "question-1");
    await busyWritten({ params: { uid: "teacher-anna" } });
    expect(entry("teacher-anna")).toMatchObject({ busy: false });
  });

  test("only a flag is published, never which question the teacher is on", async () => {
    await markTeacherBusy("teacher-anna", "question-1");
    await busyWritten({ params: { uid: "teacher-anna" } });

    expect(JSON.stringify(entry("teacher-anna"))).not.toContain("question-1");
  });

  test("going busy keeps the time the teacher came online", async () => {
    await republishTeacherPresence("teacher-anna");
    clock.nowMs += 5 * MINUTE;

    await markTeacherBusy("teacher-anna", "question-1");
    await busyWritten({ params: { uid: "teacher-anna" } });

    expect(entry("teacher-anna")).toMatchObject({ since: START_MS, busy: true });
  });

  test("a mark past the longest possible session is published as free", async () => {
    fakeRtdb.write("teachers/teacher-anna/busy", {
      questionId: "lost",
      since: START_MS - 46 * MINUTE,
    });

    await republishTeacherPresence("teacher-anna");

    expect(entry("teacher-anna")).toMatchObject({ busy: false });
  });

  test("an offline teacher has no entry, busy or not", async () => {
    fakeRtdb.write("teachers/teacher-anna/status", "offline");
    await markTeacherBusy("teacher-anna", "question-1");
    await busyWritten({ params: { uid: "teacher-anna" } });

    expect(entry("teacher-anna")).toBeUndefined();
  });

  test("a late release for an earlier question leaves the current session alone", async () => {
    await markTeacherBusy("teacher-anna", "question-2");

    await releaseTeacherBusy("teacher-anna", "question-1");
    await busyWritten({ params: { uid: "teacher-anna" } });

    expect(fakeRtdb.read("teachers/teacher-anna/busy")).toMatchObject({ questionId: "question-2" });
    expect(entry("teacher-anna")).toMatchObject({ busy: true });
  });
});
