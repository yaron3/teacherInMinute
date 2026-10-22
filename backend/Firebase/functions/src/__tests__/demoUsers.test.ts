/**
 * Demo users: marking them from the admin console, and every statistic leaving
 * them out — the dashboard, the platform averages and the online history.
 * Runs the real callables against the in-memory Firebase.
 */

import { FakeTimestamp, clock, fakeFirestore, fakeRtdb, resetFakeFirebase } from "./support/fakeFirebase";

jest.mock("firebase-admin", () => {
  const fake = require("./support/fakeFirebase");
  return { database: () => fake.fakeRtdb, firestore: () => fake.fakeFirestore, auth: () => ({}) };
});
jest.mock("firebase-admin/firestore", () => {
  const fake = require("./support/fakeFirebase");
  return { Timestamp: fake.FakeTimestamp, FieldValue: fake.FakeFieldValue };
});
jest.mock("firebase-functions", () => ({ logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() } }));
jest.mock("firebase-functions/v2/https", () => ({
  onCall: (a: unknown, b?: unknown) => b ?? a,
  HttpsError: class extends Error { constructor(public code: string, message: string) { super(message); } },
}));
jest.mock("firebase-functions/v2/firestore", () => ({ onDocumentWritten: (_p: string, h: unknown) => h }));
jest.mock("firebase-functions/v2/database", () => ({ onValueWritten: (_p: string, h: unknown) => h }));
jest.mock("firebase-functions/v2/scheduler", () => ({ onSchedule: (_s: unknown, h: unknown) => h }));
jest.mock("../accountDeletion", () => ({}));
jest.mock("../pilot", () => ({ PILOT_COLLECTION: "pilotRegistrations" }));

import { adminDashboardStatus, adminSetDemoUsers } from "../admin";
import { takeUnreachableTeachersOffline } from "../keepAlive";
import { PRESENCE_HOURLY_COLLECTION, hourStartOf } from "../presenceHistory";
import { onUserRoleChange, recordQuestionConnected } from "../stats";

const NOW = Date.UTC(2026, 9, 22, 12, 0, 0);
const MINUTE = 60_000;
const ADMIN = { auth: { uid: "admin", token: { email: "yaronj3@gmail.com", email_verified: true, admin: true } } };

const call = (fn: unknown, data: unknown = {}) => (fn as (req: unknown) => Promise<any>)({ ...ADMIN, data });
const ts = (ms: number) => FakeTimestamp.fromMillis(ms);

function seedUser(uid: string, role: "student" | "teacher", demo = false) {
  fakeFirestore.write(`users/${uid}`, { role, fullName: uid, ...(demo ? { isDemoUser: true } : {}) }, false);
}

function seedQuestion(id: string, fields: Record<string, unknown>) {
  fakeFirestore.write(`questions/${id}`, { createdAt: ts(NOW - 60 * MINUTE), ...fields }, false);
}

beforeEach(() => {
  resetFakeFirebase(NOW);
  jest.spyOn(Date, "now").mockImplementation(() => clock.nowMs);
});

afterEach(() => jest.restoreAllMocks());

describe("adminSetDemoUsers", () => {
  test("marks and unmarks users, creating a document for an account without one", async () => {
    seedUser("anna", "student");

    await call(adminSetDemoUsers, { uids: ["anna", "guest-1"], isDemo: true });
    expect(fakeFirestore.read("users/anna")).toMatchObject({ role: "student", isDemoUser: true });
    expect(fakeFirestore.read("users/guest-1")).toEqual({ isDemoUser: true });

    await call(adminSetDemoUsers, { uids: ["anna"], isDemo: false });
    expect(fakeFirestore.read("users/anna")).toEqual({ role: "student", fullName: "anna" });
  });

  test("recounts registered teachers without the demo ones", async () => {
    seedUser("t-real", "teacher");
    seedUser("t-demo", "teacher");

    await call(adminSetDemoUsers, { uids: ["t-demo"], isDemo: true });
    expect(fakeFirestore.read("stats/platform")).toMatchObject({ registeredTeacherCount: 1 });

    await call(adminSetDemoUsers, { uids: ["t-demo"], isDemo: false });
    expect(fakeFirestore.read("stats/platform")).toMatchObject({ registeredTeacherCount: 2 });
  });

  test("rejects a bad request", async () => {
    await expect(call(adminSetDemoUsers, { uids: [], isDemo: true })).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(call(adminSetDemoUsers, { uids: ["a"], isDemo: "yes" })).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(
      (adminSetDemoUsers as any)({ auth: { uid: "x", token: { email: "x@y.com", email_verified: true } }, data: { uids: ["a"], isDemo: true } })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });
});

describe("the role-change trigger", () => {
  test("recounts when a teacher is marked as a demo user", async () => {
    seedUser("t-real", "teacher");
    seedUser("t-demo", "teacher", true);
    const snap = (data: Record<string, unknown>) => ({ data: () => data });

    await (onUserRoleChange as any)({
      data: { before: snap({ role: "teacher" }), after: snap({ role: "teacher", isDemoUser: true }) },
    });
    expect(fakeFirestore.read("stats/platform")).toMatchObject({ registeredTeacherCount: 1 });
  });
});

describe("adminDashboardStatus", () => {
  beforeEach(() => {
    seedUser("s-real", "student");
    seedUser("s-demo", "student", true);
    seedUser("t-real", "teacher");
    seedUser("t-demo", "teacher", true);

    seedQuestion("q-real", { studentUid: "s-real", status: "completed", acceptedByTeacher: "t-real", acceptedAt: ts(NOW - 59 * MINUTE) });
    seedQuestion("q-demo-student", { studentUid: "s-demo", status: "completed", acceptedByTeacher: "t-real", acceptedAt: ts(NOW - 50 * MINUTE) });
    seedQuestion("q-demo-teacher", { studentUid: "s-real", status: "completed", acceptedByTeacher: "t-demo", acceptedAt: ts(NOW - 50 * MINUTE) });
    seedQuestion("q-demo-both", { studentUid: "s-demo", status: "completed", acceptedByTeacher: "t-demo", acceptedAt: ts(NOW - 50 * MINUTE) });
    seedQuestion("q-real-waiting", { studentUid: "s-real", status: "searching", createdAt: ts(NOW - 5 * MINUTE) });
    seedQuestion("q-demo-waiting", { studentUid: "s-demo", status: "searching", createdAt: ts(NOW - 9 * MINUTE) });
    seedQuestion("q-demo-unanswered", { studentUid: "s-demo", status: "unanswered" });

    fakeFirestore.write("paymentCheckouts/p-real", { uid: "s-real", status: "completed", priceCents: 1000, currency: "ILS" }, false);
    fakeFirestore.write("paymentCheckouts/p-demo", { uid: "s-demo", status: "completed", priceCents: 9000, currency: "ILS" }, false);
    fakeFirestore.write("lessons/l-demo", { studentUid: "s-demo", teacherUid: "t-real", status: "in_progress" }, false);

    fakeRtdb.write("teachers/t-real", { status: "online" });
    fakeRtdb.write("teachers/t-demo", { status: "online" });
    fakeRtdb.write("onlineTeachers/t-real", { displayName: "t-real", subjects: [], since: NOW });
    fakeRtdb.write("onlineTeachers/t-demo", { displayName: "t-demo", subjects: [], since: NOW });
  });

  test("leaves demo users out of every figure", async () => {
    const d = await call(adminDashboardStatus);

    expect(d.demoUsers).toBe(2);
    expect(d.users.total).toBe(2);
    expect(d.teachers.total).toBe(1);
    expect(d.teachers.online).toBe(1);
    expect(d.questions.completed).toBe(1);
    expect(d.questions.searching).toBe(1);
    expect(d.questions.unanswered).toBe(0);
    expect(d.questions.oldestSearching.id).toBe("q-real-waiting");
    expect(d.revenue.totalCents).toBe(1000);
    expect(d.revenue.completedPayments).toBe(1);
    expect(d.lessons.active).toEqual([]);
    expect(d.lastDay.questions).toMatchObject({ asked: 2, answered: 1, notAnswered: 0, avgWaitSeconds: 60 });
  });

  test("still lists a demo teacher online, flagged, so they can be taken offline", async () => {
    const d = await call(adminDashboardStatus);
    expect(d.teachers.list.map((t: any) => [t.uid, t.demo]).sort()).toEqual([["t-demo", true], ["t-real", false]]);
  });
});

describe("platform statistics", () => {
  test("a connect time involving a demo user is not averaged in", async () => {
    seedUser("s-real", "student");
    seedUser("t-demo", "teacher", true);

    await recordQuestionConnected("q1", NOW - 30_000, NOW, ["s-real", "t-demo"]);
    expect(fakeFirestore.read("stats/platform")).toBeUndefined();

    await recordQuestionConnected("q2", NOW - 30_000, NOW, ["s-real"]);
    expect(fakeFirestore.read("stats/platform")).toMatchObject({ connectedQuestionCount: 1, averageConnectSeconds: 30 });
  });

  test("the online-teacher history skips demo teachers", async () => {
    seedUser("t-real", "teacher");
    seedUser("t-demo", "teacher", true);
    fakeRtdb.write("teachers/t-real", { status: "online", lastSeenAt: NOW });
    fakeRtdb.write("teachers/t-demo", { status: "online", lastSeenAt: NOW });

    await takeUnreachableTeachersOffline();

    expect(fakeFirestore.read(`${PRESENCE_HOURLY_COLLECTION}/${hourStartOf(NOW)}`)).toMatchObject({
      samples: 1,
      onlineSum: 1,
      uids: ["t-real"],
    });
  });
});
