/**
 * The Realtime Database rules, run against the real rules engine.
 *
 * Write permission in RTDB *cascades*: a `.write` that grants access at
 * `questions/$qid` grants it everywhere beneath, and no rule further down can
 * take it back. That is why "only the teacher may clear the board" could not be
 * added as a rule on `board/strokes` alone — the grant had to move off the
 * question node onto its children, which risks silently denying a write the app
 * depends on.
 *
 * So this covers both halves: the one thing that must now be refused, and every
 * path the iOS and Android clients write, which must all still work.
 *
 * These need the database emulator, so they are kept out of `npm test` by the
 * `.emulator.test.ts` suffix. Run them with:
 *
 *     npm run test:rules
 */
import * as fs from "fs";
import * as path from "path";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { ref, remove, set } from "firebase/database";

const TEACHER = "teacher-uid";
const STUDENT = "student-uid";
const STRANGER = "stranger-uid";
const QID = "q1";

/** A question names its two people under either spelling, depending on who
 *  wrote the node, so both have to behave the same. */
const SHAPES: Array<[string, Record<string, string>]> = [
  ["teacherId/studentId", { teacherId: TEACHER, studentId: STUDENT }],
  ["teacherUid/studentUid", { teacherUid: TEACHER, studentUid: STUDENT }],
];

const RULES_PATH = path.join(__dirname, "..", "..", "..", "database.rules.json");

let testEnv: RulesTestEnvironment;

/**
 * `firebase emulators:exec` announces the emulator through
 * FIREBASE_DATABASE_EMULATOR_HOST. Falling back to the port firebase.json
 * pins lets the suite also run against an emulator started by hand.
 */
function emulatorAddress(): { host: string; port: number } {
  const announced = process.env.FIREBASE_DATABASE_EMULATOR_HOST;
  if (!announced) return { host: "127.0.0.1", port: 9000 };
  const colon = announced.lastIndexOf(":");
  return {
    host: announced.slice(0, colon) || "127.0.0.1",
    port: Number(announced.slice(colon + 1)),
  };
}

beforeAll(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "demo-teacher-in-a-moment",
    database: {
      rules: fs.readFileSync(RULES_PATH, "utf8"),
      ...emulatorAddress(),
    },
  });
});

afterAll(async () => {
  await testEnv?.cleanup();
});

function db(uid: string) {
  return testEnv.authenticatedContext(uid).database();
}

const stroke = (uid: string) => ({
  points: [{ x: 10, y: 20 }, { x: 30, y: 40 }],
  createdAt: 1_700_000_000_000,
  senderUid: uid,
});

describe.each(SHAPES)("database rules (%s)", (_name, people) => {
  beforeEach(async () => {
    await testEnv.clearDatabase();
    await testEnv.withSecurityRulesDisabled(async (context) => {
      // As the dispatcher leaves it, plus a stroke from each side to delete.
      await set(ref(context.database(), `questions/${QID}`), {
        ...people,
        status: "dispatched",
        text: "why is the derivative of x^2 equal to 2x?",
        board: {
          strokes: {
            "stroke-teacher": stroke(TEACHER),
            "stroke-student": stroke(STUDENT),
          },
        },
      });
    });
  });

  // ─── what the change is for ────────────────────────────────────────────────

  it("lets the teacher clear the board", async () => {
    await assertSucceeds(remove(ref(db(TEACHER), `questions/${QID}/board/strokes`)));
  });

  it("refuses to let the student clear the board", async () => {
    await assertFails(remove(ref(db(STUDENT), `questions/${QID}/board/strokes`)));
  });

  it("refuses to let the student clear it one stroke at a time", async () => {
    // Including their own: an undo would be a separate decision, and looping
    // over `strokes` is the same wipe by another name.
    await assertFails(
      remove(ref(db(STUDENT), `questions/${QID}/board/strokes/stroke-teacher`))
    );
    await assertFails(
      remove(ref(db(STUDENT), `questions/${QID}/board/strokes/stroke-student`))
    );
  });

  it("refuses to let the student overwrite a stroke", async () => {
    // Replacing the teacher's stroke with a degenerate one erases it just as
    // surely as deleting it, so the student is create-only under `strokes`.
    await assertFails(
      set(ref(db(STUDENT), `questions/${QID}/board/strokes/stroke-teacher`), stroke(STUDENT))
    );
  });

  it("lets the teacher remove a single stroke", async () => {
    await assertSucceeds(
      remove(ref(db(TEACHER), `questions/${QID}/board/strokes/stroke-student`))
    );
  });

  // ─── what must keep working: every path the clients write ──────────────────

  it("lets either side draw", async () => {
    await assertSucceeds(
      set(ref(db(TEACHER), `questions/${QID}/board/strokes/t2`), stroke(TEACHER))
    );
    await assertSucceeds(
      set(ref(db(STUDENT), `questions/${QID}/board/strokes/s2`), stroke(STUDENT))
    );
  });

  it("lets either side send a message", async () => {
    for (const uid of [TEACHER, STUDENT]) {
      await assertSucceeds(
        set(ref(db(uid), `questions/${QID}/messages/m-${uid}`), {
          text: "hello",
          senderUid: uid,
          senderRole: uid === TEACHER ? "teacher" : "student",
          createdAt: 1_700_000_000_000,
          kind: "text",
        })
      );
    }
  });

  it("lets either side report its viewport", async () => {
    for (const [uid, role] of [[TEACHER, "teacher"], [STUDENT, "student"]]) {
      await assertSucceeds(
        set(ref(db(uid), `questions/${QID}/board/viewports/${role}`), {
          x: 0, y: 0, width: 900, height: 1600, updatedAt: 1_700_000_000_000,
        })
      );
    }
  });

  it("lets either side pause the chat and flag pending media", async () => {
    for (const [uid, role] of [[TEACHER, "teacher"], [STUDENT, "student"]]) {
      await assertSucceeds(
        set(ref(db(uid), `questions/${QID}/chatPaused/${role}`), true)
      );
      await assertSucceeds(
        set(ref(db(uid), `questions/${QID}/mediaPending/${role}`), true)
      );
    }
  });

  it("lets either side tell the other what holds up its setup, and clear it", async () => {
    // A permission prompt it is waiting on, cleared once answered, then a
    // cancel — the three things ChatSessionService.setConnectionSetupSignal
    // writes.
    for (const [uid, role] of [[TEACHER, "teacher"], [STUDENT, "student"]]) {
      const entry = ref(db(uid), `questions/${QID}/connectionSetup/${role}`);
      await assertSucceeds(set(entry, "microphone"));
      await assertSucceeds(remove(entry));
      await assertSucceeds(set(entry, "cancelled"));
    }
  });

  it("lets either side switch the conversation type", async () => {
    await assertSucceeds(
      set(ref(db(TEACHER), `questions/${QID}/conversationType`), "video")
    );
  });

  it("lets the teacher accept the question", async () => {
    // markQuestionAccepted writes these three together.
    await assertSucceeds(set(ref(db(TEACHER), `questions/${QID}/status`), "accepted"));
    await assertSucceeds(
      set(ref(db(TEACHER), `questions/${QID}/acceptedAt`), 1_700_000_000_000)
    );
    await assertSucceeds(set(ref(db(TEACHER), `questions/${QID}/teacherId`), TEACHER));
  });

  it("lets either side append to the question text", async () => {
    for (const uid of [TEACHER, STUDENT]) {
      await assertSucceeds(set(ref(db(uid), `questions/${QID}/text`), "more"));
      await assertSucceeds(set(ref(db(uid), `questions/${QID}/questionText`), "more"));
    }
  });

  // ─── and nobody else gets in ───────────────────────────────────────────────

  it("keeps everyone else out", async () => {
    const outsider = db(STRANGER);
    await assertFails(
      set(ref(outsider, `questions/${QID}/board/strokes/x`), stroke(STRANGER))
    );
    await assertFails(remove(ref(outsider, `questions/${QID}/board/strokes`)));
    await assertFails(set(ref(outsider, `questions/${QID}/status`), "accepted"));
    await assertFails(
      set(ref(outsider, `questions/${QID}/messages/x`), { text: "hi" })
    );
    // Nobody else can tell a teacher their student left.
    await assertFails(
      set(ref(outsider, `questions/${QID}/connectionSetup/student`), "cancelled")
    );
  });
});
