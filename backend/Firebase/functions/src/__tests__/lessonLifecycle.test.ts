const mockEnqueue = jest.fn();
const mockTaskQueueName = jest.fn();

// ─── Fakes ───────────────────────────────────────────────────────────────────
// A Firestore and an RTDB small enough to read in one sitting. The write path
// resolves the few field sentinels these handlers use, so `arrayUnion` behaves
// like arrayUnion rather than being stored as an object.

type DocData = Record<string, unknown>;
const store = new Map<string, DocData>();
const rtdb = new Map<string, unknown>();

function resolveSentinels(existing: DocData, data: DocData): DocData {
  const next: DocData = { ...existing };
  for (const [key, value] of Object.entries(data)) {
    const sentinel = value as { __arrayUnion?: unknown[]; __serverTimestamp?: boolean };
    if (sentinel && typeof sentinel === "object" && Array.isArray(sentinel.__arrayUnion)) {
      const current = Array.isArray(next[key]) ? (next[key] as unknown[]) : [];
      next[key] = [...new Set([...current, ...sentinel.__arrayUnion])];
      continue;
    }
    if (sentinel && typeof sentinel === "object" && sentinel.__serverTimestamp) {
      next[key] = { __timestamp: "server" };
      continue;
    }
    next[key] = value;
  }
  return next;
}

function docSnapshot(path: string) {
  const data = store.get(path);
  return {
    exists: data !== undefined,
    id: path.split("/").pop() as string,
    ref: docRef(path),
    data: () => data,
  };
}

function docRef(path: string) {
  return {
    id: path.split("/").pop() as string,
    path,
    get: async () => docSnapshot(path),
    set: async (data: DocData, options?: { merge?: boolean }) => {
      store.set(path, resolveSentinels(options?.merge ? store.get(path) ?? {} : {}, data));
    },
    update: async (data: DocData) => {
      store.set(path, resolveSentinels(store.get(path) ?? {}, data));
    },
    collection: (name: string) => collectionRef(`${path}/${name}`),
  };
}

type FakeDocRef = ReturnType<typeof docRef>;

function collectionRef(path: string) {
  const query = (predicate: (data: DocData) => boolean, limit?: number) => ({
    where: (field: string, _op: string, value: unknown) =>
      query((data) => predicate(data) && data[field] === value, limit),
    limit: (n: number) => query(predicate, n),
    get: async () => {
      const matches = [...store.entries()]
        .filter(([key]) => key.startsWith(`${path}/`) && key.split("/").length === path.split("/").length + 1)
        .filter(([, data]) => predicate(data))
        .slice(0, limit ?? Infinity)
        .map(([key]) => docSnapshot(key));
      return { empty: matches.length === 0, size: matches.length, docs: matches };
    },
  });

  return {
    doc: (id: string) => docRef(`${path}/${id}`),
    where: (field: string, op: string, value: unknown) => query(() => true).where(field, op, value),
    limit: (n: number) => query(() => true).limit(n),
  };
}

const fakeFirestore = {
  collection: (name: string) => collectionRef(name),
  runTransaction: async <T>(
    body: (tx: {
      get: (ref: FakeDocRef) => Promise<ReturnType<typeof docSnapshot>>;
      update: (ref: FakeDocRef, data: DocData) => void;
      set: (ref: FakeDocRef, data: DocData, options?: { merge?: boolean }) => void;
    }) => Promise<T>
  ): Promise<T> =>
    body({
      get: (ref) => ref.get(),
      update: (ref, data) => void ref.update(data),
      set: (ref, data, options) => void ref.set(data, options),
    }),
  batch: () => {
    const operations: Array<() => Promise<void>> = [];
    const batch = {
      set: (ref: FakeDocRef, data: DocData, options?: { merge?: boolean }) => {
        operations.push(() => ref.set(data, options));
        return batch;
      },
      update: (ref: FakeDocRef, data: DocData) => {
        operations.push(() => ref.update(data));
        return batch;
      },
      commit: async () => {
        for (const run of operations) await run();
      },
    };
    return batch;
  },
};

const fakeDatabase = {
  ref: (path: string) => ({
    once: async () => ({
      exists: () => rtdb.has(path),
      val: () => rtdb.get(path) ?? null,
    }),
    remove: async () => {
      rtdb.delete(path);
    },
    update: async (data: DocData) => {
      rtdb.set(path, { ...((rtdb.get(path) as DocData) ?? {}), ...data });
    },
  }),
};

jest.mock("firebase-admin", () => ({
  firestore: () => fakeFirestore,
  database: () => fakeDatabase,
}));

jest.mock("firebase-admin/firestore", () => ({
  FieldValue: {
    serverTimestamp: () => ({ __serverTimestamp: true }),
    arrayUnion: (...values: unknown[]) => ({ __arrayUnion: values }),
    increment: (n: number) => ({ __increment: n }),
  },
  Timestamp: {
    now: () => ({ __timestamp: "now", toMillis: () => 1_700_000_000_000 }),
    fromDate: (date: Date) => ({ __timestamp: date.getTime(), toMillis: () => date.getTime() }),
    fromMillis: (millis: number) => ({ __timestamp: millis, toMillis: () => millis }),
  },
}));

jest.mock("firebase-admin/functions", () => ({
  getFunctions: () => ({
    taskQueue: (name: string) => {
      mockTaskQueueName(name);
      return { enqueue: (...args: unknown[]) => mockEnqueue(name, ...args) };
    },
  }),
}));

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

jest.mock("firebase-functions/v2/https", () => ({
  onCall: (handler: unknown) => handler,
  HttpsError: class HttpsError extends Error {
    constructor(public code: string, message: string, public details?: unknown) {
      super(message);
    }
  },
}));

jest.mock("firebase-functions/v2/tasks", () => ({
  onTaskDispatched: (_options: unknown, handler: unknown) => handler,
}));

jest.mock("uuid", () => ({ v4: () => "lesson-1" }));

jest.mock("../pricing", () => ({
  resolvePricingForStudent: jest.fn().mockResolvedValue({
    currency: "ILS",
    pricePerMinute: 2,
    exchangeRateToUsd: 4,
    teacherShare: 0.75,
  }),
  getConnectionFeeCents: jest.fn().mockResolvedValue(50),
}));

jest.mock("../dispatch", () => ({
  backfillPendingQuestionsForTeacher: jest.fn().mockResolvedValue(undefined),
}));

const mockReleaseTeacherBusy = jest.fn().mockResolvedValue(undefined);
jest.mock("../busy", () => ({
  releaseTeacherBusy: (...args: unknown[]) => mockReleaseTeacherBusy(...args),
}));

import {
  endAbandonedLesson,
  endLesson,
  extendLessonMinutes,
  forceEndLesson,
  startLesson,
} from "../lessons";
import { backfillPendingQuestionsForTeacher } from "../dispatch";

type TaskHandler = (req: { data: { questionId: string } }) => Promise<void>;
type CallableHandler = (request: {
  auth?: { uid: string };
  data: Record<string, unknown>;
}) => Promise<Record<string, unknown>>;

const runAbandonedCheck = endAbandonedLesson as unknown as TaskHandler;
const callStartLesson = startLesson as unknown as CallableHandler;
const callEndLesson = endLesson as unknown as CallableHandler;

const QUESTION_PATH = "questions/q-1";

function seedQuestion(overrides: DocData = {}): void {
  store.set(QUESTION_PATH, {
    studentUid: "student-1",
    acceptedByTeacher: "teacher-1",
    topic: "algebra",
    status: "accepted",
    acceptedAt: { toMillis: () => 1_700_000_000_000 },
    ...overrides,
  });
  rtdb.set(QUESTION_PATH, { studentUid: "student-1", teacherUid: "teacher-1", acceptedAt: 1_700_000_000_000 });
}

function question(): DocData {
  return store.get(QUESTION_PATH) ?? {};
}

beforeEach(() => {
  jest.clearAllMocks();
  store.clear();
  rtdb.clear();
});

describe("endAbandonedLesson", () => {
  test("writes off a lesson the student never joined, charging nobody", async () => {
    seedQuestion({ joinedParticipants: ["teacher-1"] });

    await runAbandonedCheck({ data: { questionId: "q-1" } });

    expect(question()).toMatchObject({
      status: "cancelled",
      endedBy: "system",
      endedReason: "student_never_joined",
      billedSeconds: 0,
      cost: 0,
      teacherEarnings: 0,
    });
    // Removing the live node is what ends the teacher's session.
    expect(rtdb.has(QUESTION_PATH)).toBe(false);
  });

  test("writes off a lesson nobody joined at all", async () => {
    seedQuestion();

    await runAbandonedCheck({ data: { questionId: "q-1" } });

    expect(question().status).toBe("cancelled");
  });

  test("leaves a lesson the student did join", async () => {
    seedQuestion({ status: "in_progress", joinedParticipants: ["teacher-1", "student-1"] });

    await runAbandonedCheck({ data: { questionId: "q-1" } });

    expect(question().status).toBe("in_progress");
    expect(rtdb.has(QUESTION_PATH)).toBe(true);
  });

  test.each(["completed", "cancelled"])("leaves a question already %s", async (status) => {
    seedQuestion({ status, cost: 12 });

    await runAbandonedCheck({ data: { questionId: "q-1" } });

    expect(question()).toMatchObject({ status, cost: 12 });
  });

  test("settles the lesson document the teacher opened", async () => {
    seedQuestion({ status: "in_progress", lessonId: "lesson-1", joinedParticipants: ["teacher-1"] });
    store.set("lessons/lesson-1", { questionId: "q-1", status: "in_progress" });

    await runAbandonedCheck({ data: { questionId: "q-1" } });

    expect(store.get("lessons/lesson-1")).toMatchObject({
      status: "completed",
      endedBy: "system",
      cost: 0,
      teacherEarnings: 0,
    });
  });
});

describe("startLesson", () => {
  test("records who joined and arms the hard cap", async () => {
    seedQuestion();

    await expect(
      callStartLesson({ auth: { uid: "student-1" }, data: { questionId: "q-1" } })
    ).resolves.toEqual({ lessonId: "lesson-1" });

    expect(question()).toMatchObject({
      status: "in_progress",
      joinedParticipants: ["student-1"],
    });
    expect(mockEnqueue).toHaveBeenCalledWith(
      "forceEndLesson",
      { lessonId: "lesson-1" },
      { scheduleDelaySeconds: 30 * 60 }
    );
  });

  // Both apps call this as they connect, so arriving second is ordinary.
  test("is idempotent for the second participant", async () => {
    seedQuestion();

    await callStartLesson({ auth: { uid: "student-1" }, data: { questionId: "q-1" } });
    await expect(
      callStartLesson({ auth: { uid: "teacher-1" }, data: { questionId: "q-1" } })
    ).resolves.toEqual({ lessonId: "lesson-1" });

    expect(question().joinedParticipants).toEqual(["student-1", "teacher-1"]);
  });

  test("refuses anyone who is not on the question", async () => {
    seedQuestion();

    await expect(
      callStartLesson({ auth: { uid: "stranger" }, data: { questionId: "q-1" } })
    ).rejects.toThrow("Not a participant in this lesson");
  });
});

describe("the student's minute allowance", () => {
  /** Timestamp.now() is pinned in the fakes, so the billing clock is fixed. */
  const NOW_MS = 1_700_000_000_000;

  test("startLesson publishes what the student can afford", async () => {
    seedQuestion();
    store.set("users/student-1", { remainingMinutes: 20 });

    await callStartLesson({ auth: { uid: "student-1" }, data: { questionId: "q-1" } });

    const saved = question();
    expect(saved.minutesAvailable).toBe(20);
    expect(saved.heldSeconds).toBe(0);
    const deadline = (saved.minutesDeadlineAt as { __timestamp: number }).__timestamp;
    expect(deadline - Date.now()).toBeGreaterThan(19 * 60_000);
    expect(deadline - Date.now()).toBeLessThanOrEqual(20 * 60_000);

    // The apps count down against the live node.
    expect(rtdb.get(QUESTION_PATH)).toMatchObject({ minutesAvailable: 20 });
  });

  test("a student with nothing left starts already held", async () => {
    seedQuestion();
    store.set("users/student-1", { remainingMinutes: 0 });

    await callStartLesson({ auth: { uid: "student-1" }, data: { questionId: "q-1" } });

    const deadline = (question().minutesDeadlineAt as { __timestamp: number }).__timestamp;
    expect(question().minutesAvailable).toBe(0);
    expect(deadline).toBeLessThanOrEqual(Date.now());
  });

  // The clock is pinned rather than allowed a tolerance: held seconds are
  // computed from two separate reads of the clock, so a loaded machine turns an
  // exact expectation into a flake and a loose one into a test that proves
  // little.
  test("buying more lifts the hold and banks the wait", async () => {
    const nowSpy = jest.spyOn(Date, "now").mockReturnValue(NOW_MS);
    try {
      seedQuestion({
        status: "in_progress",
        minutesAvailable: 10,
        heldSeconds: 0,
        minutesDeadlineAt: { toMillis: () => NOW_MS - 120_000 },
      });

      await expect(extendLessonMinutes("student-1", 10)).resolves.toBe(true);

      const saved = question();
      expect(saved.minutesAvailable).toBe(20);
      // The two minutes spent deciding to buy are not billed...
      expect(saved.heldSeconds).toBe(120);
      // ...and the ten just bought start from now, not from the old deadline,
      // so they are not eaten by the time spent buying them.
      expect((saved.minutesDeadlineAt as { __timestamp: number }).__timestamp).toBe(
        NOW_MS + 10 * 60_000
      );
    } finally {
      nowSpy.mockRestore();
    }
  });

  test.each([
    ["a student with no lesson running", "student-2", 10],
    ["a nonsense number of minutes", "student-1", 0],
  ])("does nothing for %s", async (_label, uid, minutes) => {
    seedQuestion({ status: "in_progress", minutesAvailable: 10 });

    await expect(extendLessonMinutes(uid as string, minutes as number)).resolves.toBe(false);
    expect(question().minutesAvailable).toBe(10);
  });

  test("held time is not billed", async () => {
    // Ten minutes on the clock, the last two of them held for want of minutes.
    seedQuestion({ status: "in_progress", lessonId: "lesson-1" });
    rtdb.set(QUESTION_PATH, {
      studentUid: "student-1",
      teacherUid: "teacher-1",
      acceptedAt: NOW_MS - 660_000,
      startedAt: NOW_MS - 600_000,
      minutesDeadlineAt: NOW_MS - 120_000,
    });

    await callEndLesson({ auth: { uid: "teacher-1" }, data: { questionId: "q-1" } });

    const saved = question();
    expect(saved.heldSeconds).toBe(120);
    // 8 billable minutes at 2 a minute, not the 10 on the wall clock.
    expect(saved.durationSeconds).toBe(480);
    expect(saved.cost).toBe(16);
    expect(saved.teacherEarnings).toBe(12);
    expect(store.get("users/student-1")).toMatchObject({
      remainingMinutes: { __increment: -8 },
    });
  });
});

describe("endLesson when the other side got there first", () => {
  test("reports success rather than an error", async () => {
    seedQuestion({ status: "completed" });
    rtdb.delete(QUESTION_PATH);

    await expect(
      callEndLesson({ auth: { uid: "teacher-1" }, data: { questionId: "q-1" } })
    ).resolves.toMatchObject({ success: true, alreadyEnded: true });
  });

  test("still fails when the lesson is not over", async () => {
    seedQuestion();
    rtdb.delete(QUESTION_PATH);

    await expect(
      callEndLesson({ auth: { uid: "teacher-1" }, data: { questionId: "q-1" } })
    ).rejects.toThrow();
  });
});

describe("every way a session ends frees the teacher", () => {
  test("endLesson, before the teacher is offered the next question", async () => {
    seedQuestion({ status: "in_progress", startedAt: { toMillis: () => 1_700_000_060_000 } });
    const order: string[] = [];
    mockReleaseTeacherBusy.mockImplementationOnce(async () => void order.push("release"));
    (backfillPendingQuestionsForTeacher as jest.Mock).mockImplementationOnce(
      async () => void order.push("backfill")
    );

    await callEndLesson({ auth: { uid: "student-1" }, data: { questionId: "q-1" } });

    expect(mockReleaseTeacherBusy).toHaveBeenCalledWith("teacher-1", "q-1");
    expect(order).toEqual(["release", "backfill"]);
  });

  test("endAbandonedLesson, when the student never turned up", async () => {
    seedQuestion();

    await runAbandonedCheck({ data: { questionId: "q-1" } });

    expect(mockReleaseTeacherBusy).toHaveBeenCalledWith("teacher-1", "q-1");
  });

  test("but not endAbandonedLesson on a lesson the student did join", async () => {
    seedQuestion({ joinedParticipants: ["student-1", "teacher-1"] });

    await runAbandonedCheck({ data: { questionId: "q-1" } });

    expect(mockReleaseTeacherBusy).not.toHaveBeenCalled();
  });

  test("forceEndLesson, at the hard cap", async () => {
    seedQuestion({
      status: "in_progress",
      lessonId: "lesson-1",
      startedAt: { toMillis: () => 1_700_000_060_000 },
    });
    store.set("lessons/lesson-1", { questionId: "q-1", status: "in_progress" });

    await (forceEndLesson as unknown as (req: { data: { lessonId: string } }) => Promise<void>)({
      data: { lessonId: "lesson-1" },
    });

    expect(mockReleaseTeacherBusy).toHaveBeenCalledWith("teacher-1", "q-1");
  });
});
