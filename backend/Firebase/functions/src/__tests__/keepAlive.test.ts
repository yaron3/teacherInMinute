/**
 * The keep-alive watchdog, run against the in-memory Firebase: whom it takes
 * offline, whom it leaves alone, and that a keep-alive landing mid-sweep wins.
 */

import { clock, FakeRtdbRef, fakeRtdb, resetFakeFirebase } from "./support/fakeFirebase";

jest.mock("firebase-admin", () => {
  const fake = require("./support/fakeFirebase");
  return { database: () => fake.fakeRtdb, firestore: () => fake.fakeFirestore };
});

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

jest.mock("firebase-functions/v2/scheduler", () => ({
  onSchedule: jest.fn((_schedule: unknown, handler: unknown) => handler),
}));

jest.mock("firebase-functions/v2/database", () => ({
  onValueWritten: jest.fn((_path: string, handler: unknown) => handler),
}));

import { onSchedule } from "firebase-functions/v2/scheduler";

import { takeUnreachableTeachersOffline, teacherKeepAliveWatchdog } from "../keepAlive";
import { republishTeacherPresence } from "../presence";

/** Taken before any test runs: the schedule is declared once, at import. */
const [schedule] = (onSchedule as unknown as jest.Mock).mock.calls[0];

const START_MS = Date.UTC(2026, 8, 25, 9, 0, 0);
const MINUTE = 60_000;

function online(uid: string, fields: Record<string, unknown> = {}): void {
  fakeRtdb.write(`teachers/${uid}`, {
    status: "online",
    availability: "available",
    subjects: ["algebra"],
    ...fields,
  });
}

function status(uid: string): unknown {
  return fakeRtdb.read(`teachers/${uid}/status`);
}

beforeEach(() => {
  resetFakeFirebase(START_MS);
  jest.spyOn(Date, "now").mockImplementation(() => clock.nowMs);
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe("the keep-alive watchdog", () => {
  test("takes offline a teacher silent for three minutes with no push token", async () => {
    online("teacher-anna", { lastSeenAt: START_MS - 3 * MINUTE });

    expect(await takeUnreachableTeachersOffline()).toEqual(["teacher-anna"]);
    expect(status("teacher-anna")).toBe("offline");
  });

  test("changes only the status, leaving what the teacher asked for as it was", async () => {
    online("teacher-anna", { lastSeenAt: START_MS - 5 * MINUTE });

    await takeUnreachableTeachersOffline();

    // `availability` still says they want questions, which is what lets their
    // app's next keep-alive put them straight back.
    expect(fakeRtdb.read("teachers/teacher-anna")).toEqual({
      status: "offline",
      availability: "available",
      subjects: ["algebra"],
      lastSeenAt: START_MS - 5 * MINUTE,
    });
  });

  test("leaves a teacher whose app is still sending keep-alives", async () => {
    online("teacher-anna", { lastSeenAt: START_MS - 2 * MINUTE });

    expect(await takeUnreachableTeachersOffline()).toEqual([]);
    expect(status("teacher-anna")).toBe("online");
  });

  test("leaves a silent teacher who can still be reached by push", async () => {
    online("teacher-anna", { lastSeenAt: START_MS - 60 * MINUTE, fcmToken: "fcm-anna" });

    expect(await takeUnreachableTeachersOffline()).toEqual([]);
    expect(status("teacher-anna")).toBe("online");
  });

  test("leaves an app from before the keep-alive to its old rules", async () => {
    online("teacher-anna");

    expect(await takeUnreachableTeachersOffline()).toEqual([]);
    expect(status("teacher-anna")).toBe("online");
  });

  test("does not touch a teacher who is already offline", async () => {
    fakeRtdb.write("teachers/teacher-anna", {
      status: "offline",
      availability: "dnd",
      lastSeenAt: START_MS - 60 * MINUTE,
    });

    expect(await takeUnreachableTeachersOffline()).toEqual([]);
    expect(fakeRtdb.read("teachers/teacher-anna")).toEqual({
      status: "offline",
      availability: "dnd",
      lastSeenAt: START_MS - 60 * MINUTE,
    });
  });

  test("sorts a mixed roster in one sweep", async () => {
    online("teacher-alive", { lastSeenAt: START_MS - 30_000 });
    online("teacher-pushable", { lastSeenAt: START_MS - 10 * MINUTE, fcmToken: "fcm-p" });
    online("teacher-gone", { lastSeenAt: START_MS - 10 * MINUTE });
    online("teacher-also-gone", { lastSeenAt: START_MS - 4 * MINUTE, fcmToken: "" });
    online("teacher-legacy");

    expect((await takeUnreachableTeachersOffline()).sort()).toEqual([
      "teacher-also-gone",
      "teacher-gone",
    ]);
    expect(status("teacher-alive")).toBe("online");
    expect(status("teacher-pushable")).toBe("online");
    expect(status("teacher-legacy")).toBe("online");
  });

  test("a keep-alive that lands after the sweep read the roster wins", async () => {
    online("teacher-anna", { lastSeenAt: START_MS - 4 * MINUTE });

    // The app comes back between the sweep's query and its write.
    const transaction = FakeRtdbRef.prototype.transaction;
    jest.spyOn(FakeRtdbRef.prototype, "transaction").mockImplementationOnce(function (
      this: FakeRtdbRef,
      update: (current: unknown) => unknown
    ) {
      fakeRtdb.write("teachers/teacher-anna/lastSeenAt", clock.nowMs);
      return transaction.call(this, update);
    });

    expect(await takeUnreachableTeachersOffline()).toEqual([]);
    expect(status("teacher-anna")).toBe("online");
  });

  test("one teacher's failed write does not stop the rest of the sweep", async () => {
    online("teacher-anna", { lastSeenAt: START_MS - 4 * MINUTE });
    online("teacher-ben", { lastSeenAt: START_MS - 4 * MINUTE });

    const transaction = FakeRtdbRef.prototype.transaction;
    let calls = 0;
    jest.spyOn(FakeRtdbRef.prototype, "transaction").mockImplementation(function (
      this: FakeRtdbRef,
      update: (current: unknown) => unknown
    ) {
      calls += 1;
      if (calls === 1) return Promise.reject(new Error("network"));
      return transaction.call(this, update);
    });

    expect(await takeUnreachableTeachersOffline()).toHaveLength(1);
  });

  test("taking a teacher offline takes them off the students' list", async () => {
    online("teacher-anna", { lastSeenAt: START_MS });
    await republishTeacherPresence("teacher-anna");
    expect(fakeRtdb.read("onlineTeachers/teacher-anna")).toBeDefined();

    clock.nowMs += 3 * MINUTE;
    await takeUnreachableTeachersOffline();
    // What the status trigger in ./presence does with the write.
    await republishTeacherPresence("teacher-anna");

    expect(fakeRtdb.read("onlineTeachers/teacher-anna")).toBeUndefined();
  });

  test("the app's next keep-alive brings a teacher back", async () => {
    online("teacher-anna", { lastSeenAt: START_MS - 4 * MINUTE });
    await takeUnreachableTeachersOffline();
    expect(status("teacher-anna")).toBe("offline");

    // What a keep-alive writes: status and the server's time, nothing else.
    await fakeRtdb.ref("teachers/teacher-anna").update({ status: "online", lastSeenAt: clock.nowMs });

    expect(await takeUnreachableTeachersOffline()).toEqual([]);
    expect(status("teacher-anna")).toBe("online");
  });

  test("runs every minute", async () => {
    expect(schedule).toBe("every 1 minutes");

    online("teacher-anna", { lastSeenAt: START_MS - 3 * MINUTE });
    await (teacherKeepAliveWatchdog as unknown as () => Promise<void>)();

    expect(status("teacher-anna")).toBe("offline");
  });
});
