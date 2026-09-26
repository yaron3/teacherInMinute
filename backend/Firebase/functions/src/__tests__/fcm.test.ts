/**
 * The invite push, and what happens to a teacher's token when FCM says it
 * will never deliver again. ./keepAlive keeps a silent teacher online for as
 * long as they have a push token, so a dead one left in place would keep a
 * teacher who uninstalled the app in the pool for good.
 */

import { FakeRtdbRef, fakeRtdb, resetFakeFirebase } from "./support/fakeFirebase";

const mockSend = jest.fn();

jest.mock("firebase-admin", () => {
  const fake = require("./support/fakeFirebase");
  return {
    database: () => fake.fakeRtdb,
    messaging: () => ({ send: (...args: unknown[]) => mockSend(...args) }),
  };
});

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

import { sendInvitePush } from "../fcm";

const TOKEN = "fcm-anna";

/** Shaped like firebase-admin's FirebaseMessagingError, which is all fcm.ts reads. */
function fcmError(code: string): Error & { code: string } {
  return Object.assign(new Error(code), { code });
}

function invite(): Promise<void> {
  return sendInvitePush({
    teacherUid: "teacher-anna",
    fcmToken: TOKEN,
    questionId: "question-1",
    topic: "algebra",
    studentName: "Maya",
    questionText: "2x + 5 = 15",
    wave: 1,
    ttlSeconds: 90,
  });
}

beforeEach(() => {
  resetFakeFirebase(Date.UTC(2026, 8, 25, 9, 0, 0));
  mockSend.mockReset();
  fakeRtdb.write("teachers/teacher-anna", { status: "online", fcmToken: TOKEN });
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe("a token FCM reports dead", () => {
  test.each([
    "messaging/registration-token-not-registered",
    "messaging/invalid-registration-token",
  ])("is dropped from the teacher's record (%s)", async (code) => {
    mockSend.mockRejectedValue(fcmError(code));

    await invite();

    expect(fakeRtdb.read("teachers/teacher-anna/fcmToken")).toBeUndefined();
    expect(fakeRtdb.read("teachers/teacher-anna/status")).toBe("online");
  });

  test("is not confused with a newer token the app registered since", async () => {
    fakeRtdb.write("teachers/teacher-anna/fcmToken", "fcm-anna-reinstalled");
    mockSend.mockRejectedValue(fcmError("messaging/registration-token-not-registered"));

    await invite();

    expect(fakeRtdb.read("teachers/teacher-anna/fcmToken")).toBe("fcm-anna-reinstalled");
  });

  test("is dropped without failing the invite when the cleanup itself fails", async () => {
    mockSend.mockRejectedValue(fcmError("messaging/registration-token-not-registered"));
    jest.spyOn(FakeRtdbRef.prototype, "transaction").mockRejectedValueOnce(new Error("network"));

    await expect(invite()).resolves.toBeUndefined();
  });
});

describe("a token that is merely failing", () => {
  test("is kept through an error that says nothing about the token", async () => {
    mockSend.mockRejectedValue(fcmError("messaging/internal-error"));

    await expect(invite()).resolves.toBeUndefined();

    expect(fakeRtdb.read("teachers/teacher-anna/fcmToken")).toBe(TOKEN);
  });

  test("is kept, and pushed to, when the send succeeds", async () => {
    mockSend.mockResolvedValue("message-id");

    await invite();

    expect(mockSend).toHaveBeenCalledWith(expect.objectContaining({ token: TOKEN }));
    expect(fakeRtdb.read("teachers/teacher-anna/fcmToken")).toBe(TOKEN);
  });
});
