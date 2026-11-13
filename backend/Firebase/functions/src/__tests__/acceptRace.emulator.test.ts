/**
 * Several teachers accepting the same question at the same moment, against the
 * real Firestore and Realtime Database emulators.
 *
 * waveRouting.test.ts covers the accept rules against an in-memory Firebase,
 * but that fake runs one transaction at a time, so it cannot show what happens
 * when two claims really overlap. Here the real acceptInvite runs for every
 * teacher at once and the emulators arbitrate, as production does. Whatever the
 * timing, exactly one teacher may get the lesson, and the others must be told
 * the question is taken in a way the app can tell apart from an error.
 *
 * QA test plan: IOS-D-14, AND-D-14, X-03.
 *
 * Needs both emulators, so it is kept out of `npm test` by the
 * `.emulator.test.ts` suffix. Run it with:
 *
 *     npm run test:emulator
 */
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

const PROJECT_ID = "demo-teacher-in-a-moment";

jest.mock("firebase-functions", () => ({
  ...jest.requireActual("firebase-functions"),
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

// The callable's handler, without the HTTP wrapper around it.
jest.mock("firebase-functions/v2/https", () => ({
  ...jest.requireActual("firebase-functions/v2/https"),
  onCall: jest.fn((_options: unknown, handler: unknown) => handler),
}));

// The edges acceptInvite reaches past the two databases.
jest.mock("../livekit", () => ({
  lessonRoomName: (qid: string) => `lesson_${qid}`,
  mintLiveKitToken: jest.fn(async () => ({ token: "livekit-token", expiresAt: new Date(0) })),
}));
jest.mock("../fcm", () => ({
  ...jest.requireActual("../fcm"),
  sendInvitePush: jest.fn(),
  sendNoMatchPush: jest.fn(),
  sendAcceptedPush: jest.fn(),
}));
jest.mock("../stats", () => ({
  ...jest.requireActual("../stats"),
  recordQuestionConnected: jest.fn(async () => undefined),
}));
jest.mock("../rateLimit", () => ({
  ...jest.requireActual("../rateLimit"),
  recordSessionStart: jest.fn(async () => undefined),
}));
jest.mock("../lessons", () => ({
  ...jest.requireActual("../lessons"),
  enqueueAbandonedLessonCheck: jest.fn(async () => undefined),
}));

type Callable = (request: { auth: { uid: string }; data: unknown }) => Promise<unknown>;
type Rejection = { code?: string; details?: { reason?: string } };

let acceptInvite: Callable;
let firestore: admin.firestore.Firestore;
let rtdb: admin.database.Database;

beforeAll(() => {
  for (const variable of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_DATABASE_EMULATOR_HOST"]) {
    if (!process.env[variable]) {
      throw new Error(`${variable} is not set: run this suite with \`npm run test:emulator\``);
    }
  }
  // questions.ts reads admin.firestore() and admin.database() as it loads, so
  // the app has to exist before it is required.
  admin.initializeApp({
    projectId: PROJECT_ID,
    databaseURL: `https://${PROJECT_ID}-default-rtdb.firebaseio.com`,
  });
  firestore = admin.firestore();
  rtdb = admin.database();
  acceptInvite = require("../questions").acceptInvite as Callable;
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app?.delete()));
});

let round = 0;

/** A searching question already sent to `teachers`, each holding a pending
 *  invite and a card on their dashboard, as dispatch leaves it. Fresh ids every
 *  round, since a winner stays busy afterwards. */
async function questionInvitedTo(teacherCount: number): Promise<{ qid: string; teachers: string[] }> {
  round += 1;
  const qid = `race-q${round}-${Date.now()}`;
  const student = `race-student-${round}`;
  const teachers = Array.from({ length: teacherCount }, (_, i) => `race-r${round}-teacher-${i + 1}`);
  const now = Date.now();

  const qRef = firestore.collection("questions").doc(qid);
  await qRef.set({
    studentUid: student,
    status: "searching",
    topic: "algebra",
    text: "Solve 2x + 3 = 11 for x",
    dispatchWave: 1,
    alreadyInvited: teachers,
    createdAt: Timestamp.fromMillis(now),
    updatedAt: Timestamp.fromMillis(now),
  });
  await Promise.all([
    firestore.collection("users").doc(student).set({ fullName: "Race Student", role: "student" }),
    ...teachers.map((uid) =>
      Promise.all([
        qRef.collection("invites").doc(uid).set({
          teacherUid: uid,
          response: "pending",
          wave: 1,
          invitedAt: Timestamp.fromMillis(now),
          expiresAt: Timestamp.fromMillis(now + 90_000),
        }),
        firestore.collection("users").doc(uid).set({ fullName: `Teacher ${uid}`, role: "teacher" }),
        rtdb.ref(`teachers/${uid}`).set({ status: "online", displayName: uid, subjects: { algebra: true } }),
        rtdb.ref(`teacherInvites/${uid}/${qid}`).set({ questionId: qid, wave: 1 }),
      ])
    ),
  ]);
  return { qid, teachers };
}

/** Every teacher taps Accept at once. */
async function acceptAllAtOnce(qid: string, teachers: string[]) {
  return Promise.allSettled(
    teachers.map((uid) => acceptInvite({ auth: { uid }, data: { questionId: qid } }))
  );
}

async function expectExactlyOneWinner(qid: string, teachers: string[]): Promise<void> {
  const results = await acceptAllAtOnce(qid, teachers);

  const winners = teachers.filter((_, i) => results[i].status === "fulfilled");
  expect(winners).toHaveLength(1);
  const [winner] = winners;

  // Each loser is told the question is taken, with the reason the app reads to
  // show "another teacher took it" instead of a generic error.
  const losses = results.filter((r): r is PromiseRejectedResult => r.status === "rejected");
  expect(losses).toHaveLength(teachers.length - 1);
  for (const loss of losses) {
    const error = loss.reason as Rejection;
    expect(error.code).toBe("already-exists");
    expect(error.details?.reason).toBe("question_unavailable");
  }

  const question = (await firestore.collection("questions").doc(qid).get()).data();
  expect(question?.status).toBe("accepted");
  expect(question?.acceptedByTeacher).toBe(winner);

  for (const uid of teachers) {
    const invite = (await firestore.doc(`questions/${qid}/invites/${uid}`).get()).data();
    expect(invite?.response).toBe(uid === winner ? "accept" : "pending");

    // Every card is gone, the winner's and everyone else's.
    const card = await rtdb.ref(`teacherInvites/${uid}/${qid}`).once("value");
    expect(card.exists()).toBe(false);

    // Only the winner is taken out of the pool.
    const busy = (await rtdb.ref(`teachers/${uid}/busy`).once("value")).val();
    if (uid === winner) {
      expect(busy?.questionId).toBe(qid);
    } else {
      expect(busy).toBeNull();
    }
  }
}

describe("teachers who accept the same question at the same moment", () => {
  jest.setTimeout(60_000);

  // The QA exit criterion asks for at least five clean runs of the race.
  test.each([1, 2, 3, 4, 5])("three teachers: exactly one gets the lesson (run %i)", async () => {
    const { qid, teachers } = await questionInvitedTo(3);
    await expectExactlyOneWinner(qid, teachers);
  });

  test("ten teachers, every wave's worth at once: still exactly one", async () => {
    const { qid, teachers } = await questionInvitedTo(10);
    await expectExactlyOneWinner(qid, teachers);
  });

  test("a teacher who taps again after losing is still refused", async () => {
    const { qid, teachers } = await questionInvitedTo(3);
    await expectExactlyOneWinner(qid, teachers);

    const question = (await firestore.collection("questions").doc(qid).get()).data();
    const loser = teachers.find((uid) => uid !== question?.acceptedByTeacher)!;

    await expect(acceptInvite({ auth: { uid: loser }, data: { questionId: qid } })).rejects.toMatchObject({
      code: "already-exists",
      details: { reason: "question_unavailable" },
    });
    const after = (await firestore.collection("questions").doc(qid).get()).data();
    expect(after?.acceptedByTeacher).toBe(question?.acceptedByTeacher);
  });
});

// IOS-E-03 / AND-E-03: one teacher signed in on two phones, both online, taps
// Accept on both at once.
describe("the same teacher accepting on two phones at the same moment", () => {
  jest.setTimeout(60_000);

  test.each([1, 2, 3])("gets the lesson once, and the other phone is told it is taken (run %i)", async () => {
    const { qid, teachers } = await questionInvitedTo(1);
    const [teacher] = teachers;

    const results = await Promise.allSettled([
      acceptInvite({ auth: { uid: teacher }, data: { questionId: qid } }),
      acceptInvite({ auth: { uid: teacher }, data: { questionId: qid } }),
    ]);

    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    const [loss] = results.filter((r): r is PromiseRejectedResult => r.status === "rejected");
    expect((loss.reason as Rejection).details?.reason).toBe("question_unavailable");

    const question = (await firestore.collection("questions").doc(qid).get()).data();
    expect(question).toMatchObject({ status: "accepted", acceptedByTeacher: teacher });
    const busy = (await rtdb.ref(`teachers/${teacher}/busy`).once("value")).val();
    expect(busy?.questionId).toBe(qid);
    const lessons = await firestore.collection("lessons").where("questionId", "==", qid).get();
    expect(lessons.size).toBeLessThanOrEqual(1);
  });
});
