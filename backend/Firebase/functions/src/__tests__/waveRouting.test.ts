/**
 * Wave routing, end to end, against an in-memory Firebase.
 *
 * Ten virtual teachers, all online for algebra and each with a different
 * rating, and virtual students — two for the concurrent-question scenarios, a
 * third who asks while a teacher is in a session. Questions go in through the
 * real createQuestion, waves fire from the task queue on a simulated clock through
 * the real evaluateWave, teachers claim through the real acceptInvite, and the
 * ranking is the real rankTeachers. Only the edges — push, LiveKit, pricing,
 * stats, rate limits — are stubbed.
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
}));
jest.mock("../rateLimit", () => ({
  checkQuestionAllowance: jest.fn(async () => ({ allowed: true })),
  recordSessionStart: jest.fn(async () => undefined),
}));
jest.mock("../lessons", () => ({
  enqueueAbandonedLessonCheck: jest.fn(async () => undefined),
}));

import { evaluateWave, questionWatchdog } from "../dispatch";
import { createQuestion, acceptInvite, cancelQuestion } from "../questions";
import { WAVE_SIZES, WAVE_TIMEOUT_SECONDS } from "../types";

// ─── The virtual roster ──────────────────────────────────────────────────────

/** Best first. Every one of them is online and teaches algebra, so rating is
 *  the only thing that separates them in the ranking. */
const TEACHERS_BY_RATING: Array<[uid: string, rating: number]> = [
  ["teacher-anna", 4.95],
  ["teacher-ben", 4.9],
  ["teacher-carmen", 4.8],
  ["teacher-dan", 4.7],
  ["teacher-eli", 4.6],
  ["teacher-fay", 4.5],
  ["teacher-gil", 4.4],
  ["teacher-hila", 4.3],
  ["teacher-idan", 4.2],
  ["teacher-jo", 4.1],
];

const RANKED = TEACHERS_BY_RATING.map(([uid]) => uid);
const STUDENTS = ["student-maya", "student-noam", "student-omer"];

/** The order they are written to RTDB in, deliberately not the rating order,
 *  so a pass cannot come from the dispatcher reading keys in insertion order. */
const SIGN_IN_ORDER = [7, 2, 9, 0, 5, 3, 8, 1, 6, 4];

const START_MS = Date.UTC(2026, 8, 23, 9, 0, 0);

function seedRoster(): void {
  for (const index of SIGN_IN_ORDER) {
    const [uid, rating] = TEACHERS_BY_RATING[index];
    fakeRtdb.write(`teachers/${uid}`, {
      status: "online",
      subjects: ["algebra"],
      ratingAvg: rating,
      ratingCount: 20,
      displayName: uid,
      fcmToken: `fcm-${uid}`,
    });
  }

  for (const uid of STUDENTS) {
    fakeFirestore.write(`users/${uid}`, { fullName: uid, remainingMinutes: 60 }, false);
  }
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

async function ask(studentUid: string): Promise<string> {
  const result = await (createQuestion as unknown as Callable)({
    auth: { uid: studentUid },
    data: { topic: "algebra", text: "How do I solve 2x + 3 = 11?", conversationType: "text" },
  });
  return result.questionId as string;
}

function accept(teacherUid: string, questionId: string) {
  return (acceptInvite as unknown as Callable)({ auth: { uid: teacherUid }, data: { questionId } });
}

/** Moves the clock to `seconds` after the start, running every Cloud Task that
 *  falls due on the way, each at the moment it was scheduled for. */
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
}

function invitesFor(qid: string): Record<string, InviteView> {
  return fakeFirestore.readCollection(`questions/${qid}/invites`) as unknown as Record<
    string,
    InviteView
  >;
}

/** Teachers holding a live invite in `wave` — neither withdrawn nor declined. */
function pendingInWave(qid: string, wave: number): string[] {
  return Object.entries(invitesFor(qid))
    .filter(([, inv]) => inv.wave === wave && inv.response === "pending")
    .map(([uid]) => uid)
    .sort(byRank);
}

/** Teachers who currently have this question on their dashboard. */
function dashboardsShowing(qid: string): string[] {
  return RANKED.filter((uid) => fakeRtdb.read(`teacherInvites/${uid}/${qid}`) !== undefined);
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

describe("wave routing with 10 teachers", () => {
  test("the roster is what the scenarios assume", () => {
    expect(WAVE_SIZES).toEqual([3, 5, 10]);
    expect(WAVE_TIMEOUT_SECONDS).toBe(12);
    expect(RANKED).toHaveLength(10);
  });

  test("wave 1 goes to the 3 best-rated teachers, and only them", async () => {
    const qid = await ask("student-maya");

    const top3 = RANKED.slice(0, 3);
    expect(pendingInWave(qid, 1)).toEqual(top3);
    expect(Object.keys(invitesFor(qid)).sort(byRank)).toEqual(top3);
    expect(dashboardsShowing(qid)).toEqual(top3);
    expect(question(qid)).toMatchObject({
      status: "searching",
      dispatchWave: 1,
      alreadyInvited: expect.arrayContaining(top3),
    });
    expect(question(qid).alreadyInvited).toHaveLength(3);

    // The next wave is scheduled 12 seconds out, not run now.
    expect(fakeTasks.history).toContainEqual(
      expect.objectContaining({
        queue: "evaluateWave",
        payload: { questionId: qid, wave: 1 },
        delaySeconds: 12,
      })
    );
  });

  test("nobody new is added before 12 seconds, and the next 5 are added at 12", async () => {
    const qid = await ask("student-maya");
    const top3 = RANKED.slice(0, 3);

    await advanceTo(11.9);
    expect(dashboardsShowing(qid)).toEqual(top3);
    expect(question(qid).dispatchWave).toBe(1);

    await advanceTo(12);
    const next5 = RANKED.slice(3, 8);
    expect(question(qid).dispatchWave).toBe(2);
    expect(pendingInWave(qid, 2)).toEqual(next5);
    // Wave 2 adds to wave 1 rather than replacing it: the first three keep
    // their invites for the full 90 seconds.
    expect(pendingInWave(qid, 1)).toEqual(top3);
    expect(dashboardsShowing(qid)).toEqual(RANKED.slice(0, 8));
  });

  test("wave 3 at 24 seconds reaches the remaining teachers", async () => {
    const qid = await ask("student-maya");

    await advanceTo(23.9);
    expect(question(qid).dispatchWave).toBe(2);
    expect(dashboardsShowing(qid)).toEqual(RANKED.slice(0, 8));

    await advanceTo(24);
    expect(question(qid).dispatchWave).toBe(3);
    expect(pendingInWave(qid, 3)).toEqual(RANKED.slice(8));
    expect(dashboardsShowing(qid)).toEqual(RANKED);
    expect(question(qid).alreadyInvited).toHaveLength(10);
  });

  test("no teacher is invited twice across waves", async () => {
    const qid = await ask("student-maya");
    await advanceTo(24);

    const invited = question(qid).alreadyInvited as string[];
    expect(new Set(invited).size).toBe(invited.length);
    expect(Object.keys(invitesFor(qid))).toHaveLength(10);
  });
});

describe("two students asking at the same time", () => {
  test("both questions go to the same 3 best-rated teachers", async () => {
    const [q1, q2] = await Promise.all([ask("student-maya"), ask("student-noam")]);
    const top3 = RANKED.slice(0, 3);

    expect(q1).not.toBe(q2);
    expect(pendingInWave(q1, 1)).toEqual(top3);
    expect(pendingInWave(q2, 1)).toEqual(top3);
    for (const uid of top3) {
      expect(Object.keys(fakeRtdb.read(`teacherInvites/${uid}`) as object).sort()).toEqual(
        [q1, q2].sort()
      );
    }
  });

  test("when one teacher takes the first question, the second keeps 3 live invites in wave 1", async () => {
    const [q1, q2] = await Promise.all([ask("student-maya"), ask("student-noam")]);
    const [anna, ben, carmen, dan] = RANKED;

    await advanceTo(3);
    await accept(anna, q1);

    // The first student has their teacher, and the question is off everyone
    // else's dashboard.
    expect(question(q1)).toMatchObject({ status: "accepted", acceptedByTeacher: anna });
    expect(dashboardsShowing(q1)).toEqual([]);

    // The second question is still live …
    expect(question(q2)).toMatchObject({ status: "searching", dispatchWave: 1 });

    // … Anna is busy, so her invite to it is taken back …
    expect(invitesFor(q2)[anna].response).toBe("withdrawn");
    expect(fakeRtdb.read(`teacherInvites/${anna}/${q2}`)).toBeUndefined();

    // … Ben and Carmen still have it, and Dan — the next-best teacher who had
    // not seen it — is brought in, so wave 1 is back to 3.
    expect(pendingInWave(q2, 1)).toEqual([ben, carmen, dan]);
    expect(dashboardsShowing(q2)).toEqual([ben, carmen, dan]);
    expect(invitesFor(q2)[dan]).toMatchObject({ wave: 1, response: "pending" });
    expect(question(q2).alreadyInvited).toEqual(expect.arrayContaining([anna, ben, carmen, dan]));
  });

  test("the second question's next wave, at 12 seconds, skips everyone it has already reached", async () => {
    const [q1, q2] = await Promise.all([ask("student-maya"), ask("student-noam")]);
    const [anna, ben, carmen, dan] = RANKED;

    await advanceTo(3);
    await accept(anna, q1);

    await advanceTo(12);

    // The accepted question does not fan out any further.
    expect(question(q1).dispatchWave).toBe(1);
    expect(dashboardsShowing(q1)).toEqual([]);

    // The second question moves on to the five after Dan; Anna, busy teaching,
    // is not invited back.
    expect(question(q2).dispatchWave).toBe(2);
    expect(pendingInWave(q2, 1)).toEqual([ben, carmen, dan]);
    expect(pendingInWave(q2, 2)).toEqual(RANKED.slice(4, 9));
    expect(dashboardsShowing(q2)).toEqual(RANKED.slice(1, 9));
    expect(dashboardsShowing(q2)).not.toContain(anna);
  });

  test("a replacement teacher can take the second question", async () => {
    const [q1, q2] = await Promise.all([ask("student-maya"), ask("student-noam")]);
    const [anna, , , dan] = RANKED;

    await advanceTo(3);
    await accept(anna, q1);
    await advanceTo(5);
    await accept(dan, q2);

    expect(question(q2)).toMatchObject({ status: "accepted", acceptedByTeacher: dan });
    expect(dashboardsShowing(q2)).toEqual([]);
  });

  test("the busy teacher cannot also claim the second question", async () => {
    const [q1, q2] = await Promise.all([ask("student-maya"), ask("student-noam")]);
    const [anna] = RANKED;

    await advanceTo(3);
    await accept(anna, q1);

    await expect(accept(anna, q2)).rejects.toMatchObject({ code: "failed-precondition" });
    expect(question(q2).status).toBe("searching");
  });
});

describe("a student who cancels before a teacher's accept lands", () => {
  test("the accept is refused with a reason the app can tell apart", async () => {
    const qid = await ask("student-maya");
    const [anna] = RANKED;

    await advanceTo(3);
    await (cancelQuestion as unknown as Callable)({
      auth: { uid: "student-maya" },
      data: { questionId: qid },
    });

    // The teacher's app says the student cancelled, rather than dropping them
    // back on the dashboard with nothing on screen to explain it.
    await expect(accept(anna, qid)).rejects.toMatchObject({
      code: "failed-precondition",
      details: { reason: "question_cancelled" },
    });
    expect(question(qid).status).toBe("cancelled");
    expect(fakeRtdb.read(`teachers/${anna}/busy`)).toBeUndefined();
  });
});

describe("a teacher in a session is busy", () => {
  test("accepting marks the teacher busy with that question", async () => {
    const qid = await ask("student-maya");
    const [anna] = RANKED;

    await advanceTo(3);
    await accept(anna, qid);

    expect(fakeRtdb.read(`teachers/${anna}/busy`)).toEqual({
      questionId: qid,
      since: START_MS + 3000,
    });
    // Still online — the app's own status is left alone.
    expect(fakeRtdb.read(`teachers/${anna}/status`)).toBe("online");
  });

  test("a question asked during the session skips the busy teacher in every wave", async () => {
    const q1 = await ask("student-maya");
    const [anna, ben, carmen, dan] = RANKED;

    await advanceTo(3);
    await accept(anna, q1);

    await advanceTo(4);
    const q2 = await ask("student-omer");
    expect(pendingInWave(q2, 1)).toEqual([ben, carmen, dan]);

    await advanceTo(4 + 12);
    expect(pendingInWave(q2, 2)).toEqual(RANKED.slice(4, 9));

    await advanceTo(4 + 24);
    // Every free teacher has it; the one teaching never did.
    expect(dashboardsShowing(q2)).toEqual(RANKED.slice(1));
    expect(invitesFor(q2)[anna]).toBeUndefined();
  });

  test("the busy teacher cannot accept a second question", async () => {
    const q1 = await ask("student-maya");
    const [anna] = RANKED;

    await advanceTo(3);
    await accept(anna, q1);

    // Plant an invite as if one had slipped through before the mark landed.
    const q2 = await ask("student-omer");
    fakeFirestore.write(
      `questions/${q2}/invites/${anna}`,
      {
        teacherUid: anna,
        questionId: q2,
        wave: 1,
        response: "pending",
        expiresAt: { toMillis: () => START_MS + 90_000 },
      },
      false
    );

    await expect(accept(anna, q2)).rejects.toMatchObject({ code: "failed-precondition" });
    expect(question(q2).status).toBe("searching");
  });

  test("when the student cancels the accepted question, the teacher is free again", async () => {
    const q1 = await ask("student-maya");
    const [anna] = RANKED;

    await advanceTo(3);
    await accept(anna, q1);
    await (cancelQuestion as unknown as Callable)({
      auth: { uid: "student-maya" },
      data: { questionId: q1 },
    });

    expect(fakeRtdb.read(`teachers/${anna}/busy`)).toBeUndefined();

    const q2 = await ask("student-omer");
    expect(pendingInWave(q2, 1)).toEqual(RANKED.slice(0, 3));
  });

  test("a mark left behind past the longest possible session stops blocking the teacher", async () => {
    const [anna] = RANKED;
    fakeRtdb.write(`teachers/${anna}/busy`, { questionId: "lost", since: START_MS });

    await advanceTo(46 * 60);
    const qid = await ask("student-maya");

    expect(pendingInWave(qid, 1)).toEqual(RANKED.slice(0, 3));
  });
});
