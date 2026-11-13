/**
 * The emulator-only stand-in for Remote Config, against the Firestore
 * emulator: read on the emulators, ignored everywhere else.
 *
 *     npm run test:emulator
 */
import * as admin from "firebase-admin";

const PROJECT_ID = "demo-teacher-in-a-moment";

jest.mock("firebase-functions", () => ({
  ...jest.requireActual("firebase-functions"),
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

type RemoteConfigModule = typeof import("../remoteConfig");
let rc: RemoteConfigModule;

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("FIRESTORE_EMULATOR_HOST is not set: run with `npm run test:emulator`");
  }
  if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
  rc = require("../remoteConfig") as RemoteConfigModule;
});

afterEach(async () => {
  delete process.env.FUNCTIONS_EMULATOR;
  await admin.firestore().doc("emulatorRemoteConfig/values").delete();
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app?.delete()));
});

describe("Remote Config on the emulators", () => {
  jest.setTimeout(30_000);

  test("a value set for the emulators is read there", async () => {
    process.env.FUNCTIONS_EMULATOR = "true";
    await admin.firestore().doc(rc.EMULATOR_RC_OVERRIDES_DOC).set({
      signup_reward_student_minutes: 15,
      some_switch: "true",
    });

    expect(await rc.readRcNumber("signup_reward_student_minutes")).toBe(15);
    expect(await rc.readRcBoolean("some_switch")).toBe(true);
  });

  test("outside the emulators the stand-in is never read", async () => {
    await admin.firestore().doc(rc.EMULATOR_RC_OVERRIDES_DOC).set({ signup_reward_student_minutes: 15 });

    // The real template cannot be fetched for the demo project either, so
    // nothing is found.
    expect(await rc.readRcNumber("signup_reward_student_minutes")).toBeUndefined();
  });
});
