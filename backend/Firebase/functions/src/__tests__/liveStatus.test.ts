/**
 * The admin console's Live page: system checks, teachers online, and
 * questions answered in the last hour.
 */

import { FakeTimestamp, fakeFirestore, fakeRtdb, resetFakeFirebase } from "./support/fakeFirebase";

jest.mock("firebase-admin", () => {
  const fake = require("./support/fakeFirebase");
  return { database: () => fake.fakeRtdb, firestore: () => fake.fakeFirestore };
});
jest.mock("firebase-admin/firestore", () => ({
  Timestamp: require("./support/fakeFirebase").FakeTimestamp,
}));

import { readLiveStatus } from "../liveStatus";
import { PRESENCE_HOURLY_COLLECTION, hourStartOf } from "../presenceHistory";

const MIN = 60_000;
const HOUR = 60 * MIN;
const NOW = Date.UTC(2026, 10, 5, 12, 30);
const ts = (ms: number) => FakeTimestamp.fromMillis(ms);

/** A healthy system: one teacher online and published, the watchdog swept a
 *  minute ago, nothing searching. */
function healthy() {
  fakeRtdb.write("teachers/anna", { status: "online" });
  fakeRtdb.write("teachers/ben", { status: "offline" });
  fakeRtdb.write("onlineTeachers/anna", { displayName: "Anna" });
  fakeFirestore.write(`${PRESENCE_HOURLY_COLLECTION}/${hourStartOf(NOW)}`, {
    hourStartMs: hourStartOf(NOW), samples: 30, onlineSum: 30, uids: ["anna"], lastSampleMs: NOW - MIN,
  }, false);
}

function question(id: string, data: Record<string, unknown>) {
  fakeFirestore.write(`questions/${id}`, data, false);
}

const check = (s: Awaited<ReturnType<typeof readLiveStatus>>, id: string) => s.checks.find((c) => c.id === id)!;

beforeEach(() => resetFakeFirebase(NOW));

test("reports a healthy system as ok", async () => {
  healthy();
  const s = await readLiveStatus(NOW);
  expect(s.overall).toBe("ok");
  expect(s.checks.map((c) => [c.id, c.state])).toEqual([
    ["watchdog", "ok"], ["queue", "ok"], ["presence", "ok"], ["coverage", "ok"],
  ]);
  expect(s.onlineTeachers).toBe(1);
});

test("counts questions a teacher took in the last hour, and those asked", async () => {
  healthy();
  question("q1", { status: "completed", createdAt: ts(NOW - 50 * MIN), acceptedAt: ts(NOW - 49 * MIN) });
  question("q2", { status: "in_progress", createdAt: ts(NOW - 5 * MIN), acceptedAt: ts(NOW - 4 * MIN) });
  // Asked before the hour, taken inside it.
  question("q3", { status: "completed", createdAt: ts(NOW - 61 * MIN), acceptedAt: ts(NOW - 59 * MIN) });
  // Taken before the hour.
  question("q4", { status: "completed", createdAt: ts(NOW - 3 * HOUR), acceptedAt: ts(NOW - 2 * HOUR) });
  // Asked in the hour, no teacher took it.
  question("q5", { status: "unanswered", createdAt: ts(NOW - 20 * MIN) });

  const s = await readLiveStatus(NOW);
  expect(s.answeredLastHour).toBe(3);
  expect(s.askedLastHour).toBe(3);
});

test("leaves demo users out of every figure", async () => {
  healthy();
  fakeFirestore.write("users/demo-t", { isDemoUser: true }, false);
  fakeFirestore.write("users/demo-s", { isDemoUser: true }, false);
  fakeRtdb.write("teachers/demo-t", { status: "online" });
  fakeRtdb.write("onlineTeachers/demo-t", { displayName: "Demo" });
  question("q1", { studentUid: "demo-s", status: "completed", createdAt: ts(NOW - MIN), acceptedAt: ts(NOW) });
  question("q2", { studentUid: "real", acceptedByTeacher: "demo-t", status: "completed", createdAt: ts(NOW - MIN), acceptedAt: ts(NOW) });

  const s = await readLiveStatus(NOW);
  expect(s.onlineTeachers).toBe(1);
  expect(s.answeredLastHour).toBe(0);
  expect(s.askedLastHour).toBe(0);
});

test("flags a late watchdog, and a stopped one as down", async () => {
  healthy();
  const bucket = `${PRESENCE_HOURLY_COLLECTION}/${hourStartOf(NOW)}`;

  fakeFirestore.write(bucket, { lastSampleMs: NOW - 5 * MIN }, true);
  expect(check(await readLiveStatus(NOW), "watchdog").state).toBe("warn");

  fakeFirestore.write(bucket, { lastSampleMs: NOW - 15 * MIN }, true);
  const s = await readLiveStatus(NOW);
  expect(check(s, "watchdog").state).toBe("down");
  expect(s.overall).toBe("down");
});

test("finds the last sweep in the previous hour's bucket just after the hour turns", async () => {
  healthy();
  const justAfter = hourStartOf(NOW) + HOUR + 30_000;
  fakeFirestore.write(`${PRESENCE_HOURLY_COLLECTION}/${hourStartOf(NOW)}`, { lastSampleMs: justAfter - MIN }, true);
  expect(check(await readLiveStatus(justAfter), "watchdog").state).toBe("ok");
});

test("reports a watchdog with no sweeps at all as down", async () => {
  fakeRtdb.write("teachers/anna", { status: "online" });
  fakeRtdb.write("onlineTeachers/anna", {});
  expect(check(await readLiveStatus(NOW), "watchdog").state).toBe("down");
});

test("warns about questions stuck past their search deadline", async () => {
  healthy();
  question("waiting", { status: "searching", createdAt: ts(NOW - MIN), searchEndsAt: ts(NOW + MIN) });
  question("stuck", { status: "searching", createdAt: ts(NOW - 10 * MIN), searchEndsAt: ts(NOW - 5 * MIN) });

  const s = await readLiveStatus(NOW);
  expect(check(s, "queue")).toMatchObject({ state: "warn", detail: "1 question stuck past the search deadline" });
  expect(s.overall).toBe("warn");
});

test("warns when presence and the published projection disagree", async () => {
  healthy();
  fakeRtdb.write("teachers/carl", { status: "online" }); // online, but students cannot see him
  expect(check(await readLiveStatus(NOW), "presence").state).toBe("warn");
});

test("warns when no teacher is online", async () => {
  healthy();
  fakeRtdb.write("teachers/anna", { status: "offline" });
  fakeRtdb.write("onlineTeachers/anna", null);
  const s = await readLiveStatus(NOW);
  expect(s.onlineTeachers).toBe(0);
  expect(check(s, "coverage").state).toBe("warn");
});
