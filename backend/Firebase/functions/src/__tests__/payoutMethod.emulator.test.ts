/**
 * Saving a payout method against the real Firestore emulator: a new method
 * replaces the stored one whole. The in-memory fakes merge maps however they
 * are written, so only the emulator shows what `merge: true` really does to a
 * nested map — it kept a bank account behind after a switch to Bit.
 *
 *     npm run test:emulator
 */
import * as admin from "firebase-admin";

const PROJECT_ID = "demo-teacher-in-a-moment";

jest.mock("firebase-functions", () => ({
  ...jest.requireActual("firebase-functions"),
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn(), debug: jest.fn() },
}));

type Callable = { run: (request: unknown) => Promise<unknown> };
let update: Callable;

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("FIRESTORE_EMULATOR_HOST is not set: run with `npm run test:emulator`");
  }
  if (!admin.apps.length) admin.initializeApp({ projectId: PROJECT_ID });
  update = require("../earnings").updateTeacherPayoutMethod as Callable;
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app?.delete()));
});

describe("saving a payout method", () => {
  jest.setTimeout(30_000);

  test("switching from a bank account to Bit leaves no bank details behind", async () => {
    const uid = `payout-teacher-${Date.now()}`;
    const userRef = admin.firestore().doc(`users/${uid}`);
    await userRef.set({ role: "teacher", fullName: "Payout Teacher" });
    const request = (payoutMethod: Record<string, unknown>) => ({ auth: { uid }, data: { payoutMethod } });

    await update.run(request({
      type: "bank", bankCode: "04", branchNumber: "123", accountNumber: "12345678", accountHolderName: "Payout Teacher",
    }));
    expect((await userRef.get()).data()?.payoutMethod).toMatchObject({ type: "bank", accountNumber: "12345678" });

    await update.run(request({ type: "bit", phone: "0501234567" }));

    const stored = (await userRef.get()).data();
    expect(stored?.payoutMethod).toMatchObject({ type: "bit", phone: "0501234567" });
    for (const stale of ["bankCode", "bankName", "branchNumber", "accountNumber", "accountHolderName"]) {
      expect(stored?.payoutMethod).not.toHaveProperty(stale);
    }
    expect(stored?.fullName).toBe("Payout Teacher");
  });
});
