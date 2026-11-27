/**
 * Closing stale live questions and lessons: only records still live and long
 * idle are touched, and they are written off, never billed.
 */

const mockDocs = new Map<string, Record<string, unknown>>();
const mockRtdb = new Map<string, unknown>();
const mockRemoved: string[] = [];
const mockReleased: string[] = [];

jest.mock("firebase-admin", () => {
  const docRef = (collection: string, id: string): Record<string, unknown> => ({
    id,
    path: `${collection}/${id}`,
    get: async () => ({ exists: mockDocs.has(`${collection}/${id}`), data: () => mockDocs.get(`${collection}/${id}`) }),
    collection: () => ({ listDocuments: async () => [] }),
  });
  const firestore = {
    collection: (c: string) => ({
      doc: (id: string) => docRef(c, id),
      where: (field: string, _op: string, value: unknown) => ({
        get: async () => ({
          docs: [...mockDocs.entries()]
            .filter(([k, v]) => k.startsWith(`${c}/`) && v[field] === value)
            .map(([k]) => { const ref = docRef(c, k.split("/")[1]); return { id: ref.id, ref }; }),
        }),
      }),
    }),
    runTransaction: async (fn: (tx: unknown) => unknown) =>
      fn({
        get: (ref: { get: () => unknown }) => ref.get(),
        update: (ref: { path: string }, fields: Record<string, unknown>) => {
          mockDocs.set(ref.path, { ...mockDocs.get(ref.path), ...fields });
        },
      }),
  };
  const database = {
    ref: (p: string) => ({
      once: async () => ({ val: () => mockRtdb.get(p) ?? null }),
      remove: async () => { mockRemoved.push(p); },
    }),
  };
  return { firestore: () => firestore, database: () => database };
});
jest.mock("firebase-admin/firestore", () => ({
  FieldValue: { serverTimestamp: () => "SERVER_TIME" },
  Timestamp: class {},
}));
jest.mock("firebase-functions", () => ({ logger: { warn: jest.fn(), info: jest.fn(), error: jest.fn() } }));
jest.mock("../busy", () => ({
  releaseTeacherBusy: async (t: string, q: string) => { mockReleased.push(`${t}/${q}`); },
}));
jest.mock("../demoUsers", () => ({ readDemoUserUids: async () => new Set<string>() }));

import { closeStaleLiveItem, isStale, STALE_LIVE_AFTER_MS } from "../staleLive";

const NOW = Date.UTC(2026, 10, 27, 12);
const OLD = NOW - 90 * 24 * 3600 * 1000;

beforeEach(() => {
  mockDocs.clear();
  mockRtdb.clear();
  mockRemoved.length = 0;
  mockReleased.length = 0;
});

describe("isStale", () => {
  it("is stale only after a full day without activity", () => {
    expect(isStale({ updatedAt: NOW - STALE_LIVE_AFTER_MS + 1000 }, NOW)).toBe(false);
    expect(isStale({ createdAt: OLD, updatedAt: NOW - 60_000 }, NOW)).toBe(false);
    expect(isStale({ createdAt: OLD, updatedAt: OLD }, NOW)).toBe(true);
    expect(isStale({}, NOW)).toBe(true);
  });
});

describe("closeStaleLiveItem", () => {
  it("writes off a stale in-progress question and its lesson at zero, never as completed", async () => {
    mockDocs.set("questions/q1", { status: "in_progress", acceptedByTeacher: "t1", studentUid: "s1", lessonId: "l1", updatedAt: OLD });
    mockDocs.set("lessons/l1", { status: "in_progress", questionId: "q1", startedAt: OLD });

    expect(await closeStaleLiveItem({ kind: "question", id: "q1" }, NOW)).toEqual({ status: "closed" });
    expect(mockDocs.get("questions/q1")).toMatchObject({
      status: "cancelled", endedBy: "system", endedReason: "stale_closeout", billedSeconds: 0, teacherEarnings: 0, cost: 0,
    });
    expect(mockDocs.get("lessons/l1")).toMatchObject({ status: "completed", endedBy: "system", cost: 0, teacherEarnings: 0 });
    expect(mockRemoved).toEqual(expect.arrayContaining(["questions/q1", "lessonPresence/q1"]));
    expect(mockReleased).toEqual(["t1/q1"]);
  });

  it("ends a stale search as unanswered, as the search watchdog would", async () => {
    mockDocs.set("questions/q2", { status: "searching", studentUid: "s1", createdAt: OLD });
    await closeStaleLiveItem({ kind: "question", id: "q2" }, NOW);
    expect(mockDocs.get("questions/q2")?.status).toBe("unanswered");
  });

  it("skips a question that is not stale, already ended, or busy in RTDB", async () => {
    mockDocs.set("questions/fresh", { status: "accepted", updatedAt: NOW - 3600_000 });
    mockDocs.set("questions/done", { status: "completed", updatedAt: OLD });
    mockDocs.set("questions/rt", { status: "in_progress", updatedAt: OLD });
    mockRtdb.set("questions/rt", { updatedAt: NOW - 60_000 });

    expect(await closeStaleLiveItem({ kind: "question", id: "fresh" }, NOW)).toEqual({ status: "skipped", reason: "active again" });
    expect(await closeStaleLiveItem({ kind: "question", id: "done" }, NOW)).toEqual({ status: "skipped", reason: "already completed" });
    expect(await closeStaleLiveItem({ kind: "question", id: "rt" }, NOW)).toEqual({ status: "skipped", reason: "active in RTDB" });
    expect(mockDocs.get("questions/fresh")?.status).toBe("accepted");
    expect(mockRemoved).toEqual([]);
  });

  it("closes a lesson whose question already ended with the question's figures, leaving the question alone", async () => {
    const question = { status: "completed", billedSeconds: 300, totalCents: 1000, cost: 10, teacherEarnings: 7.5, updatedAt: OLD };
    mockDocs.set("questions/q3", question);
    mockDocs.set("lessons/l3", { status: "in_progress", questionId: "q3", teacherUid: "t3", startedAt: OLD });

    expect(await closeStaleLiveItem({ kind: "lesson", id: "l3" }, NOW)).toEqual({ status: "closed" });
    expect(mockDocs.get("lessons/l3")).toMatchObject({ status: "completed", billedSeconds: 300, cost: 10, teacherEarnings: 7.5 });
    expect(mockDocs.get("questions/q3")).toEqual(question);
    expect(mockReleased).toEqual(["t3/q3"]);
  });

  it("closes a lesson's live question along with it", async () => {
    mockDocs.set("questions/q4", { status: "in_progress", acceptedByTeacher: "t4", lessonId: "l4", updatedAt: OLD });
    mockDocs.set("lessons/l4", { status: "in_progress", questionId: "q4", startedAt: OLD });
    expect(await closeStaleLiveItem({ kind: "lesson", id: "l4" }, NOW)).toEqual({ status: "closed" });
    expect(mockDocs.get("questions/q4")?.status).toBe("cancelled");
    expect(mockDocs.get("lessons/l4")?.status).toBe("completed");
  });
});
