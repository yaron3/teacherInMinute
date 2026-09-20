// A Firestore small enough to reason about: one map of documents, and a
// transaction that runs its body once against it.
const store = new Map<string, Record<string, unknown>>();

function docRef(path: string) {
  return {
    path,
    get: async () => ({ exists: store.has(path), data: () => store.get(path) }),
    set: async (data: Record<string, unknown>, options?: { merge?: boolean }) => {
      store.set(path, options?.merge ? { ...(store.get(path) ?? {}), ...data } : { ...data });
    },
  };
}

const fakeFirestore = {
  collection: (name: string) => ({ doc: (id: string) => docRef(`${name}/${id}`) }),
  runTransaction: async (body: (tx: unknown) => Promise<unknown>) =>
    body({
      get: (ref: ReturnType<typeof docRef>) => ref.get(),
      set: (ref: ReturnType<typeof docRef>, data: Record<string, unknown>, options?: { merge?: boolean }) =>
        void ref.set(data, options),
    }),
};

jest.mock("firebase-admin", () => ({ firestore: () => fakeFirestore }));

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

import {
  appendSession,
  checkQuestionAllowance,
  evaluateQuestionRate,
  recordSessionStart,
} from "../rateLimit";

const NOW = 1_700_000_000_000;
const seconds = (n: number) => n * 1000;
const minutes = (n: number) => n * 60_000;

describe("evaluateQuestionRate", () => {
  test("allows a first question and records when it was asked", () => {
    expect(evaluateQuestionRate(undefined, NOW, 2, 5)).toEqual({
      allowed: true,
      kept: [NOW],
    });
  });

  test("allows one more while under both allowances", () => {
    const decision = evaluateQuestionRate([NOW - seconds(30)], NOW, 2, 5);
    expect(decision.allowed).toBe(true);
    expect(decision.kept).toEqual([NOW - seconds(30), NOW]);
  });

  test("refuses the third question inside a minute", () => {
    const decision = evaluateQuestionRate([NOW - seconds(40), NOW - seconds(10)], NOW, 2, 5);
    expect(decision).toMatchObject({ allowed: false, scope: "minute" });
    // The oldest of the two ages out 20s from now, and that is when asking works again.
    expect(decision.retryAfterSeconds).toBe(20);
  });

  test("the allowance returns as questions age out, rather than resetting on the clock", () => {
    const spent = [NOW - seconds(70), NOW - seconds(65)];
    expect(evaluateQuestionRate(spent, NOW, 2, 5).allowed).toBe(true);
  });

  test("refuses at the hourly allowance and says how long in minutes' worth of seconds", () => {
    const spent = [
      NOW - minutes(50),
      NOW - minutes(40),
      NOW - minutes(30),
      NOW - minutes(20),
      NOW - minutes(10),
    ];
    const decision = evaluateQuestionRate(spent, NOW, 2, 5);
    expect(decision).toMatchObject({ allowed: false, scope: "hour" });
    expect(decision.retryAfterSeconds).toBe(10 * 60);
  });

  test("reports the hourly wait when both allowances are spent", () => {
    const spent = [
      NOW - minutes(30),
      NOW - minutes(20),
      NOW - minutes(10),
      NOW - seconds(20),
      NOW - seconds(10),
    ];
    const decision = evaluateQuestionRate(spent, NOW, 2, 5);
    // Saying "20 seconds" would be a lie: the hour is what stands in the way.
    expect(decision.scope).toBe("hour");
  });

  test("forgets questions older than an hour", () => {
    const decision = evaluateQuestionRate(
      [NOW - minutes(90), NOW - minutes(75), NOW - minutes(10)],
      NOW,
      2,
      5
    );
    expect(decision.allowed).toBe(true);
    expect(decision.kept).toEqual([NOW - minutes(10), NOW]);
  });

  test.each([
    ["no record at all", undefined],
    ["a value that is not a list", { questionsAt: 3 }],
    ["junk entries", ["yesterday", null, NaN]],
    ["timestamps from the future", [NOW + minutes(5), NOW + minutes(9)]],
  ])("treats %s as nothing asked yet", (_label, stored) => {
    expect(evaluateQuestionRate(stored, NOW, 2, 5)).toEqual({ allowed: true, kept: [NOW] });
  });

  test("a published zero turns an allowance off", () => {
    const spent = [NOW - seconds(5), NOW - seconds(4), NOW - seconds(3)];
    expect(evaluateQuestionRate(spent, NOW, 0, 0).allowed).toBe(true);
  });

  test("never asks anyone to retry in zero seconds", () => {
    // Both spent a whole minute ago bar a millisecond.
    const decision = evaluateQuestionRate([NOW - 59_999, NOW - 59_999], NOW, 2, 5);
    expect(decision.allowed).toBe(false);
    expect(decision.retryAfterSeconds).toBeGreaterThanOrEqual(1);
  });
});

describe("appendSession", () => {
  test("keeps the last hour, oldest first", () => {
    expect(appendSession([NOW - minutes(90), NOW - minutes(5)], NOW, NOW)).toEqual([
      NOW - minutes(5),
      NOW,
    ]);
  });

  test("does not record the same question twice", () => {
    expect(appendSession([NOW - minutes(2)], NOW - minutes(2), NOW)).toEqual([NOW - minutes(2)]);
  });
});

describe("spending against Firestore", () => {
  beforeEach(() => store.clear());

  test("asking is free — checking spends nothing", async () => {
    const decision = await checkQuestionAllowance("student-1", 2, 5, NOW);

    expect(decision.allowed).toBe(true);
    // Nothing written: a question nobody answers must cost the student nothing.
    expect(store.size).toBe(0);
  });

  test("a session is what spends one", async () => {
    await recordSessionStart("student-1", NOW - seconds(10), NOW);

    expect(store.get("rateLimits/student-1")).toMatchObject({
      sessionsAt: [NOW - seconds(10)],
    });
  });

  test("sessions are stamped when the question was sent, not when it was taken", async () => {
    const askedAt = NOW - minutes(3);
    await recordSessionStart("student-1", askedAt, NOW);

    // A question that waited three minutes for a teacher does not push the
    // student's next ask three minutes further out.
    expect(store.get("rateLimits/student-1")?.sessionsAt).toEqual([askedAt]);
  });

  test("refuses the next ask once the allowance is spent", async () => {
    await recordSessionStart("student-1", NOW - seconds(30), NOW);
    await recordSessionStart("student-1", NOW - seconds(20), NOW);

    const decision = await checkQuestionAllowance("student-1", 2, 5, NOW);

    expect(decision).toMatchObject({ allowed: false, scope: "minute" });
  });

  test("one student's sessions do not count against another's", async () => {
    await recordSessionStart("student-1", NOW - seconds(30), NOW);
    await recordSessionStart("student-1", NOW - seconds(20), NOW);

    await expect(checkQuestionAllowance("student-2", 2, 5, NOW)).resolves.toMatchObject({
      allowed: true,
    });
  });
});
