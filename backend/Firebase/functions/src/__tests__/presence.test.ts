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

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentUpdated: jest.fn((_path: string, handler: unknown) => handler),
}));

import {
  changesPublishedProfile,
  onTeacherPresenceBusyWritten,
  onTeacherProfileUpdated,
  republishTeacherPresence,
} from "../presence";
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

// QA test plan IOS-G-07 / AND-G-07: "Show my profile image" off.
describe("the photo in the public online-teacher entry", () => {
  test("is the teacher's profile image by default", async () => {
    fakeFirestore.write("users/teacher-anna", { fullName: "Anna", profileImageURL: "https://img/anna.jpg" }, false);

    await republishTeacherPresence("teacher-anna");

    expect(entry("teacher-anna")).toMatchObject({ displayName: "Anna", photoUrl: "https://img/anna.jpg" });
  });

  test("is left out when the teacher turned off Show my profile image", async () => {
    fakeFirestore.write(
      "users/teacher-anna",
      { fullName: "Anna", profileImageURL: "https://img/anna.jpg", showProfileImage: false },
      false
    );

    await republishTeacherPresence("teacher-anna");

    expect(entry("teacher-anna")).toMatchObject({ displayName: "Anna", photoUrl: "" });
  });
});

describe("a teacher editing their profile while online", () => {
  type ProfileTrigger = (event: {
    params: { uid: string };
    data: { before: { data: () => Record<string, unknown> }; after: { data: () => Record<string, unknown> } };
  }) => Promise<void>;

  /** Writes users/{uid} and runs the trigger as Firestore would. */
  async function updateProfile(uid: string, before: Record<string, unknown>, after: Record<string, unknown>) {
    fakeFirestore.write(`users/${uid}`, after, false);
    await (onTeacherProfileUpdated as unknown as ProfileTrigger)({
      params: { uid },
      data: { before: { data: () => before }, after: { data: () => after } },
    });
  }

  const shown = { fullName: "Anna", profileImageURL: "https://img/anna.jpg" };

  beforeEach(async () => {
    fakeFirestore.write("users/teacher-anna", shown, false);
    await republishTeacherPresence("teacher-anna");
  });

  test("turning off Show my profile image takes the photo down at once", async () => {
    await updateProfile("teacher-anna", shown, { ...shown, showProfileImage: false });

    expect(entry("teacher-anna")).toMatchObject({ displayName: "Anna", photoUrl: "" });
  });

  test("turning it back on puts the photo back", async () => {
    await updateProfile("teacher-anna", shown, { ...shown, showProfileImage: false });
    await updateProfile("teacher-anna", { ...shown, showProfileImage: false }, { ...shown, showProfileImage: true });

    expect(entry("teacher-anna")).toMatchObject({ photoUrl: "https://img/anna.jpg" });
  });

  test("a new name or photo shows at once", async () => {
    const updated = { fullName: "Anna K.", profileImageURL: "https://img/anna-2.jpg" };
    await updateProfile("teacher-anna", shown, updated);

    expect(entry("teacher-anna")).toMatchObject({ displayName: "Anna K.", photoUrl: "https://img/anna-2.jpg" });
  });

  test("a teacher who is offline is not listed by editing their profile", async () => {
    fakeRtdb.write("teachers/teacher-anna/status", "offline");
    await republishTeacherPresence("teacher-anna");

    await updateProfile("teacher-anna", shown, { ...shown, showProfileImage: false });

    expect(entry("teacher-anna")).toBeUndefined();
  });

  test("a change to anything not shown leaves the entry alone", async () => {
    // Changed behind the trigger's back: a republish would pick it up.
    fakeFirestore.write("users/teacher-anna", { ...shown, fullName: "Changed elsewhere", remainingMinutes: 5 }, false);
    await (onTeacherProfileUpdated as unknown as ProfileTrigger)({
      params: { uid: "teacher-anna" },
      data: { before: { data: () => shown }, after: { data: () => ({ ...shown, remainingMinutes: 5 }) } },
    });

    expect(entry("teacher-anna")).toMatchObject({ displayName: "Anna" });
  });

  test("only the shown fields count as a change", () => {
    expect(changesPublishedProfile(shown, { ...shown, remainingMinutes: 3, fcmToken: "x" })).toBe(false);
    for (const field of ["fullName", "profileImageURL", "profilePhotoURL", "photoURL", "showProfileImage"]) {
      expect(changesPublishedProfile(shown, { ...shown, [field]: "changed" })).toBe(true);
    }
  });
});
