/**
 * A student's search-screen choices reaching the teachers' cards, against the
 * real Realtime Database and Firestore emulators.
 *
 * applyQuestionDetails patches each card through an RTDB transaction. On a
 * server the transaction's first pass sees the empty local cache — null even
 * for a card that exists — and the in-memory fake behind questionDetails.test
 * never does, so only the emulator shows whether the patch lands. It used to
 * abort on that first null, so a student's switch to a text lesson never
 * reached a card, and a teacher could accept an audio lesson for a student
 * waiting in text.
 *
 *     npm run test:emulator
 */
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

const PROJECT_ID = "demo-teacher-in-a-moment";
const DATABASE_URL = `https://${PROJECT_ID}-default-rtdb.firebaseio.com`;

jest.mock("firebase-functions", () => ({
  ...jest.requireActual("firebase-functions"),
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));
jest.mock("../fcm", () => ({ ...jest.requireActual("../fcm"), sendInvitePush: jest.fn() }));

type Apply = (qid: string, details: Record<string, string>) => Promise<unknown>;

let applyQuestionDetails: Apply;
/** The setup's own app, so the code under test starts with nothing cached. */
let seeding: admin.app.App;

beforeAll(() => {
  for (const variable of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_DATABASE_EMULATOR_HOST"]) {
    if (!process.env[variable]) throw new Error(`${variable} is not set: run with \`npm run test:emulator\``);
  }
  if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID, databaseURL: DATABASE_URL });
  seeding = admin.initializeApp({ projectId: PROJECT_ID, databaseURL: DATABASE_URL }, "seeding");
  applyQuestionDetails = require("../dispatch").applyQuestionDetails as Apply;
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app?.delete()));
});

/** A searching question with a pending invite and its card, as dispatch
 *  leaves them, written by the seeding app only. */
async function questionWithCard(withCard = true): Promise<{ qid: string; teacher: string }> {
  const qid = `details-q-${Date.now()}-${Math.round(Math.random() * 1e6)}`;
  const teacher = `details-teacher-${qid}`;
  const now = Timestamp.now();
  const qRef = seeding.firestore().collection("questions").doc(qid);
  await qRef.set({ status: "searching", topic: "any", conversationType: "audio", createdAt: now });
  await qRef.collection("invites").doc(teacher).set({
    teacherUid: teacher, questionId: qid, response: "pending", wave: 1, conversationType: "audio", sentAt: now,
  });
  if (withCard) {
    await seeding.database().ref(`teacherInvites/${teacher}/${qid}`).set({ topic: "any", conversationType: "audio", wave: 1 });
  }
  return { qid, teacher };
}

describe("a student's later choices reach the teacher's card", () => {
  jest.setTimeout(30_000);

  test("switching to a text lesson changes the card the teacher accepts from", async () => {
    const { qid, teacher } = await questionWithCard();

    await applyQuestionDetails(qid, { conversationType: "text" });

    const card = (await seeding.database().ref(`teacherInvites/${teacher}/${qid}`).once("value")).val();
    expect(card).toMatchObject({ conversationType: "text", topic: "any", wave: 1 });
    const invite = (await seeding.firestore().doc(`questions/${qid}/invites/${teacher}`).get()).data();
    expect(invite?.conversationType).toBe("text");
  });

  test("a card already cleared is not brought back", async () => {
    const { qid, teacher } = await questionWithCard(false);

    await applyQuestionDetails(qid, { conversationType: "text" });

    const card = await seeding.database().ref(`teacherInvites/${teacher}/${qid}`).once("value");
    expect(card.exists()).toBe(false);
  });
});
