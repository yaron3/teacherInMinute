/**
 * The student filling in their question while the search runs, end to end,
 * against an in-memory Firebase: the question is asked without a subject
 * through the real createQuestion, waves run through the real evaluateWave,
 * and the details arrive through the real updateQuestion. Only the edges —
 * push, LiveKit, pricing, stats, rate limits — are stubbed.
 */

import {
  clock,
  fakeFirestore,
  fakeRtdb,
  fakeTasks,
  resetFakeFirebase,
  ScheduledTask,
} from "./support/fakeFirebase";

jest.mock("firebase-admin", () => {
  const fake = require("./support/fakeFirebase");
  return {
    database: () => fake.fakeRtdb,
    firestore: () => fake.fakeFirestore,
  };
});

jest.mock("firebase-admin/firestore", () => {
  const fake = require("./support/fakeFirebase");
  return { FieldValue: fake.FakeFieldValue, Timestamp: fake.FakeTimestamp };
});

jest.mock("firebase-admin/functions", () => {
  const fake = require("./support/fakeFirebase");
  return { getFunctions: () => fake.fakeTasks };
});

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

jest.mock("firebase-functions/v2/https", () => ({
  onCall: jest.fn((_options: unknown, handler: unknown) => handler),
  HttpsError: class HttpsError extends Error {
    constructor(public code: string, message: string, public details?: unknown) {
      super(message);
    }
  },
}));

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentCreated: jest.fn((_options: unknown, handler: unknown) => handler),
}));

jest.mock("firebase-functions/v2/tasks", () => ({
  onTaskDispatched: jest.fn((_options: unknown, handler: unknown) => handler),
}));

jest.mock("firebase-functions/v2/database", () => ({
  onValueWritten: jest.fn((_path: string, handler: unknown) => handler),
}));

let mockNextQuestionNumber = 0;
jest.mock("uuid", () => ({ v4: () => `question-${++mockNextQuestionNumber}` }));

jest.mock("../livekit", () => ({
  lessonRoomName: (qid: string) => `lesson_${qid}`,
  mintLiveKitToken: jest.fn(async () => ({ token: "livekit-token", expiresAt: new Date(0) })),
}));

jest.mock("../fcm", () => ({
  sendInvitePush: jest.fn(),
  sendNoMatchPush: jest.fn(),
  sendAcceptedPush: jest.fn(),
}));

jest.mock("../pricing", () => ({ getConnectionFeeCents: jest.fn(async () => 50) }));
jest.mock("../stats", () => ({ recordQuestionConnected: jest.fn(async () => undefined) }));
jest.mock("../questionLimits", () => ({
  getQuestionMaxLength: jest.fn(async () => 1024),
  getQuestionRateLimits: jest.fn(async () => ({ perMinute: 10, perHour: 100 })),
  getSearchTimeoutSeconds: jest.fn(async () => 90),
}));
jest.mock("../rateLimit", () => ({
  checkQuestionAllowance: jest.fn(async () => ({ allowed: true })),
  recordSessionStart: jest.fn(async () => undefined),
}));
jest.mock("../lessons", () => ({
  enqueueAbandonedLessonCheck: jest.fn(async () => undefined),
}));

import { evaluateWave, questionWatchdog } from "../dispatch";
import { acceptInvite, createQuestion, updateQuestion } from "../questions";

// ─── The roster ──────────────────────────────────────────────────────────────

/** Best first, each teaching something different, so a subject decides who
 *  can keep the question. */
const ROSTER: Array<[uid: string, rating: number, subjects: string[]]> = [
  ["teacher-anna", 4.95, ["algebra"]],
  ["teacher-ben", 4.9, ["algebra", "geometry"]],
  ["teacher-carmen", 4.8, ["trigonometry"]],
  ["teacher-dan", 4.7, ["geometry"]],
  ["teacher-eli", 4.6, ["geometry", "calculus"]],
  ["teacher-fay", 4.5, ["algebra"]],
  ["teacher-gil", 4.4, ["geometry"]],
];

const RANKED = ROSTER.map(([uid]) => uid);
const [ANNA, BEN, CARMEN, DAN, ELI, FAY, GIL] = RANKED;
const STUDENT = "student-maya";

const START_MS = Date.UTC(2026, 8, 30, 9, 0, 0);

function seedRoster(): void {
  for (const [uid, rating, subjects] of ROSTER) {
    fakeRtdb.write(`teachers/${uid}`, {
      status: "online",
      subjects,
      ratingAvg: rating,
      ratingCount: 20,
      displayName: uid,
      fcmToken: `fcm-${uid}`,
    });
  }
  fakeFirestore.write(`users/${STUDENT}`, { fullName: STUDENT, remainingMinutes: 60 }, false);
}

// ─── Driving the functions ───────────────────────────────────────────────────

type Callable = (req: { auth?: { uid: string }; data: Record<string, unknown> }) => Promise<
  Record<string, unknown>
>;
type TaskHandler = (req: { data: Record<string, unknown> }) => Promise<void>;

const TASK_HANDLERS: Record<string, TaskHandler> = {
  evaluateWave: evaluateWave as unknown as TaskHandler,
  questionWatchdog: questionWatchdog as unknown as TaskHandler,
};

/** As the camera home asks: without a subject. */
async function askWithoutSubject(): Promise<string> {
  const result = await (createQuestion as unknown as Callable)({
    auth: { uid: STUDENT },
    data: { topic: "any", text: "How do I find the area of this shape?", conversationType: "text" },
  });
  return result.questionId as string;
}

function update(questionId: string, details: Record<string, unknown>, uid = STUDENT) {
  return (updateQuestion as unknown as Callable)({ auth: { uid }, data: { questionId, ...details } });
}

async function advanceTo(seconds: number): Promise<void> {
  const target = START_MS + seconds * 1000;
  let task: ScheduledTask | undefined;
  while ((task = fakeTasks.takeNextDue(target))) {
    clock.nowMs = task.runAtMs;
    await TASK_HANDLERS[task.queue]({ data: task.payload });
  }
  clock.nowMs = target;
}

// ─── Reading what the apps would see ─────────────────────────────────────────

interface InviteView {
  wave: number;
  response: string;
  conversationType: string;
}

function invitesFor(qid: string): Record<string, InviteView> {
  return fakeFirestore.readCollection(`questions/${qid}/invites`) as unknown as Record<
    string,
    InviteView
  >;
}

function pendingInWave(qid: string, wave: number): string[] {
  return Object.entries(invitesFor(qid))
    .filter(([, inv]) => inv.wave === wave && inv.response === "pending")
    .map(([uid]) => uid)
    .sort(byRank);
}

function dashboardsShowing(qid: string): string[] {
  return RANKED.filter((uid) => fakeRtdb.read(`teacherInvites/${uid}/${qid}`) !== undefined);
}

function card(uid: string, qid: string): Record<string, unknown> {
  return fakeRtdb.read(`teacherInvites/${uid}/${qid}`) as Record<string, unknown>;
}

function question(qid: string): Record<string, unknown> {
  return fakeFirestore.read(`questions/${qid}`) as Record<string, unknown>;
}

function byRank(a: string, b: string): number {
  return RANKED.indexOf(a) - RANKED.indexOf(b);
}

// ─── Tests ───────────────────────────────────────────────────────────────────

beforeEach(() => {
  resetFakeFirebase(START_MS);
  mockNextQuestionNumber = 0;
  jest.spyOn(Date, "now").mockImplementation(() => clock.nowMs);
  seedRoster();
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe("naming the subject while the search runs", () => {
  test("a question asked without a subject goes to the best teachers of any subject", async () => {
    const qid = await askWithoutSubject();
    expect(pendingInWave(qid, 1)).toEqual([ANNA, BEN, CARMEN]);
  });

  test("teachers who do not teach it lose the question, and teachers who do take their places", async () => {
    const qid = await askWithoutSubject();

    await expect(update(qid, { topic: "geometry" })).resolves.toEqual({
      updated: true,
      status: "searching",
    });

    expect(question(qid).topic).toBe("geometry");
    // Anna and Carmen teach no geometry: their invites are taken back and the
    // question is off their dashboards …
    expect(invitesFor(qid)[ANNA].response).toBe("withdrawn");
    expect(invitesFor(qid)[CARMEN].response).toBe("withdrawn");
    // … while Ben keeps his, and the best geometry teachers not yet asked fill
    // the two places in wave 1 that were freed.
    expect(pendingInWave(qid, 1)).toEqual([BEN, DAN, ELI]);
    expect(dashboardsShowing(qid)).toEqual([BEN, DAN, ELI]);
    expect(card(BEN, qid).topic).toBe("geometry");
    expect(card(DAN, qid).topic).toBe("geometry");
  });

  test("later waves go only to teachers of the subject", async () => {
    const qid = await askWithoutSubject();
    await update(qid, { topic: "geometry" });

    await advanceTo(12);

    expect(question(qid).dispatchWave).toBe(2);
    // Gil is the only geometry teacher left; Fay teaches algebra only.
    expect(pendingInWave(qid, 2)).toEqual([GIL]);
    expect(dashboardsShowing(qid)).toEqual([BEN, DAN, ELI, GIL]);
    expect(dashboardsShowing(qid)).not.toContain(FAY);
  });

  test("a subject fewer than three teach takes the question from nobody", async () => {
    const qid = await askWithoutSubject();
    await update(qid, { topic: "calculus" });

    // Only Eli teaches calculus: dropping the others would leave the student
    // one teacher, so all three keep the question, and see its subject.
    expect(pendingInWave(qid, 1)).toEqual([ANNA, BEN, CARMEN]);
    expect(dashboardsShowing(qid)).toEqual([ANNA, BEN, CARMEN]);
    expect(card(ANNA, qid).topic).toBe("calculus");
    expect(Object.values(invitesFor(qid)).map((inv) => inv.response)).not.toContain("withdrawn");
  });

  test("with fewer than three, later waves go to every teacher, its teachers first", async () => {
    const qid = await askWithoutSubject();
    await update(qid, { topic: "calculus" });

    await advanceTo(12);

    expect(pendingInWave(qid, 2)).toEqual([DAN, ELI, FAY, GIL]);
    expect(dashboardsShowing(qid)).toEqual(RANKED);
  });

  test("three teachers of the subject are enough to narrow it", async () => {
    const qid = await askWithoutSubject();
    // Anna, Ben and Fay teach algebra: exactly three.
    await update(qid, { topic: "algebra" });

    expect(invitesFor(qid)[CARMEN].response).toBe("withdrawn");
    expect(pendingInWave(qid, 1)).toEqual([ANNA, BEN, FAY]);
    expect(dashboardsShowing(qid)).toEqual([ANNA, BEN, FAY]);
  });

  test("going back to any subject takes nothing back", async () => {
    const qid = await askWithoutSubject();
    await update(qid, { topic: "any" });

    expect(pendingInWave(qid, 1)).toEqual([ANNA, BEN, CARMEN]);
    expect(dashboardsShowing(qid)).toEqual([ANNA, BEN, CARMEN]);
  });
});

describe("why the student is stuck and how they would like to start", () => {
  test("reach the card of every teacher holding the question", async () => {
    const qid = await askWithoutSubject();

    await update(qid, { struggle: "different_results", conversationType: "video" });

    expect(question(qid)).toMatchObject({ struggle: "different_results", conversationType: "video" });
    for (const uid of [ANNA, BEN, CARMEN]) {
      expect(card(uid, qid)).toMatchObject({
        struggle: "different_results",
        conversationType: "video",
        text: "How do I find the area of this shape?",
      });
      expect(invitesFor(qid)[uid].conversationType).toBe("video");
    }
  });

  test("reach the teachers of later waves too", async () => {
    const qid = await askWithoutSubject();
    await update(qid, { struggle: "repeating_mistake" });

    await advanceTo(12);

    expect(pendingInWave(qid, 2).length).toBeGreaterThan(0);
    for (const uid of pendingInWave(qid, 2)) {
      expect(card(uid, qid).struggle).toBe("repeating_mistake");
    }
  });

  test("a card cleared meanwhile is not brought back", async () => {
    const qid = await askWithoutSubject();
    fakeRtdb.write(`teacherInvites/${ANNA}/${qid}`, null);

    await update(qid, { struggle: "cant_solve" });

    expect(fakeRtdb.read(`teacherInvites/${ANNA}/${qid}`)).toBeUndefined();
    expect(card(BEN, qid).struggle).toBe("cant_solve");
  });
});

describe("what updateQuestion refuses", () => {
  test("another student's question", async () => {
    const qid = await askWithoutSubject();
    await expect(update(qid, { topic: "geometry" }, "student-noam")).rejects.toMatchObject({
      code: "permission-denied",
    });
    expect(question(qid).topic).toBe("any");
  });

  test("a question a teacher has already taken is left as it is", async () => {
    const qid = await askWithoutSubject();
    await (acceptInvite as unknown as Callable)({ auth: { uid: ANNA }, data: { questionId: qid } });

    await expect(update(qid, { topic: "geometry" })).resolves.toEqual({
      updated: false,
      status: "accepted",
    });
    expect(question(qid).topic).toBe("any");
  });

  test.each([
    [{ topic: "chemistry" }],
    [{ struggle: "bored" }],
    [{ conversationType: "hologram" }],
    [{}],
  ])("the invalid update %j", async (details) => {
    const qid = await askWithoutSubject();
    await expect(update(qid, details)).rejects.toMatchObject({ code: "invalid-argument" });
  });
});
