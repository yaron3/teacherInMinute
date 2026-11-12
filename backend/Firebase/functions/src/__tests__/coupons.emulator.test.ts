/**
 * Redeeming a coupon, against the real Firestore emulator — the minutes are an
 * increment inside a transaction, which the in-memory fake does not model.
 *
 * QA test plan: IOS-M-05, AND-M-05. Only a valid, unused coupon of the
 * student's own adds minutes, and it adds them once, however many times or
 * from however many devices it is redeemed.
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

jest.mock("firebase-functions/v2/https", () => ({
  ...jest.requireActual("firebase-functions/v2/https"),
  onCall: jest.fn((handler: unknown) => handler),
}));

type Callable = (request: { auth?: { uid: string }; data: unknown }) => Promise<{ minutesAdded?: number }>;

let redeemCoupon: Callable;
let firestore: admin.firestore.Firestore;

beforeAll(() => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error("FIRESTORE_EMULATOR_HOST is not set: run this suite with `npm run test:emulator`");
  }
  // coupons.ts reaches lessons.ts, which opens the database as it loads.
  if (!admin.apps.length) {
    admin.initializeApp({ projectId: PROJECT_ID, databaseURL: `https://${PROJECT_ID}-default-rtdb.firebaseio.com` });
  }
  firestore = admin.firestore();
  redeemCoupon = require("../coupons").redeemCoupon as Callable;
});

afterAll(async () => {
  await Promise.all(admin.apps.map((app) => app?.delete()));
});

let round = 0;

/** A student with `minutes` and a fresh coupon of theirs worth 30 minutes. */
async function studentWithCoupon(minutes = 10): Promise<{ uid: string; code: string }> {
  round += 1;
  const uid = `coupon-student-${round}-${Date.now()}`;
  const code = `COUPON-${round}-${Date.now()}`;
  await firestore.collection("users").doc(uid).set({ role: "student", remainingMinutes: minutes, totalMinutes: minutes });
  await firestore.collection("coupons").doc(code).set({
    studentUserId: uid,
    numberOfMinutes: 30,
    price: 12,
    createdBy: "admin-test",
  });
  return { uid, code };
}

async function minutesOf(uid: string): Promise<number> {
  return (await firestore.collection("users").doc(uid).get()).data()?.remainingMinutes;
}

describe("redeeming a coupon", () => {
  jest.setTimeout(30_000);

  test("a valid coupon adds its minutes once, and is recorded as a purchase", async () => {
    const { uid, code } = await studentWithCoupon(10);

    await expect(redeemCoupon({ auth: { uid }, data: { couponCode: code } })).resolves.toMatchObject({
      minutesAdded: 30,
    });

    expect(await minutesOf(uid)).toBe(40);
    const coupon = (await firestore.collection("coupons").doc(code).get()).data();
    expect(coupon?.activatedAt).toBeInstanceOf(Timestamp);
    const purchase = (await firestore.doc(`users/${uid}/purchases/${code}`).get()).data();
    expect(purchase).toMatchObject({ provider: "coupon", minutesPurchased: 30, minutesRemaining: 30 });
  });

  test("leading and trailing spaces in the code are ignored", async () => {
    const { uid, code } = await studentWithCoupon(0);

    await redeemCoupon({ auth: { uid }, data: { couponCode: `  ${code} ` } });

    expect(await minutesOf(uid)).toBe(30);
  });

  test("a code that does not exist adds nothing", async () => {
    const { uid } = await studentWithCoupon(10);

    await expect(redeemCoupon({ auth: { uid }, data: { couponCode: "NO-SUCH-CODE" } })).rejects.toMatchObject({
      code: "not-found",
    });
    expect(await minutesOf(uid)).toBe(10);
  });

  test("an empty code is refused", async () => {
    const { uid } = await studentWithCoupon(10);

    await expect(redeemCoupon({ auth: { uid }, data: { couponCode: "   " } })).rejects.toMatchObject({
      code: "invalid-argument",
    });
    expect(await minutesOf(uid)).toBe(10);
  });

  test("another student's coupon looks like an invalid code, and stays unused", async () => {
    const owner = await studentWithCoupon(10);
    const other = await studentWithCoupon(5);

    await expect(
      redeemCoupon({ auth: { uid: other.uid }, data: { couponCode: owner.code } })
    ).rejects.toMatchObject({ code: "not-found" });

    expect(await minutesOf(other.uid)).toBe(5);
    expect((await firestore.collection("coupons").doc(owner.code).get()).data()?.activatedAt).toBeUndefined();
  });

  test("a coupon already used adds nothing the second time", async () => {
    const { uid, code } = await studentWithCoupon(10);
    await redeemCoupon({ auth: { uid }, data: { couponCode: code } });

    await expect(redeemCoupon({ auth: { uid }, data: { couponCode: code } })).rejects.toMatchObject({
      code: "failed-precondition",
    });
    expect(await minutesOf(uid)).toBe(40);
  });

  test("redeemed from two devices at the same moment, it adds its minutes once", async () => {
    const { uid, code } = await studentWithCoupon(10);

    const results = await Promise.allSettled([
      redeemCoupon({ auth: { uid }, data: { couponCode: code } }),
      redeemCoupon({ auth: { uid }, data: { couponCode: code } }),
    ]);

    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(await minutesOf(uid)).toBe(40);
  });

  test("a signed-out caller is refused", async () => {
    const { code } = await studentWithCoupon(10);

    await expect(redeemCoupon({ data: { couponCode: code } })).rejects.toMatchObject({ code: "unauthenticated" });
  });
});
