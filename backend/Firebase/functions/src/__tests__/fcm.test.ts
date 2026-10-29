/**
 * The invite push, and what happens to a teacher's token when FCM says it
 * will never deliver again. ./keepAlive keeps a silent teacher online for as
 * long as they have a push token, so a dead one left in place would keep a
 * teacher who uninstalled the app in the pool for good.
 */

import { FakeRtdbRef, fakeRtdb, resetFakeFirebase } from "./support/fakeFirebase";

const mockSend = jest.fn();
const mockSendEach = jest.fn();

jest.mock("firebase-admin", () => {
  const fake = require("./support/fakeFirebase");
  return {
    database: () => fake.fakeRtdb,
    messaging: () => ({
      send: (...args: unknown[]) => mockSend(...args),
      sendEach: (...args: unknown[]) => mockSendEach(...args),
    }),
  };
});

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

import {
  inviteAlertTitle,
  sendAcceptedPush,
  sendAdminPush,
  sendInvitePush,
  sendNoMatchPush,
} from "../fcm";

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
  mockSendEach.mockReset();
  fakeRtdb.write("teachers/teacher-anna", { status: "online", fcmToken: TOKEN });
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe("the invite on iOS", () => {
  // A data-only push shows nothing on an iOS device whose app is suspended or
  // killed, which is the only time the push matters.
  test("carries a visible alert that expires and collapses with the invite", async () => {
    mockSend.mockResolvedValue("message-id");

    await invite();

    const apns = mockSend.mock.calls[0][0].apns;
    expect(apns.payload.aps).toEqual({
      alert: { title: "Maya needs help with algebra", body: "2x + 5 = 15" },
      sound: "default",
    });
    expect(apns.headers).toMatchObject({
      "apns-push-type": "alert",
      "apns-collapse-id": "teacher-question-question-1",
      "apns-expiration": String(Math.floor(Date.now() / 1000) + 90),
    });
  });

  test("stays data-only on Android, whose client posts its own notification", async () => {
    mockSend.mockResolvedValue("message-id");

    await invite();

    expect(mockSend.mock.calls[0][0].notification).toBeUndefined();
  });

  test.each([
    ["Maya", "algebra", "Maya needs help with algebra"],
    ["Maya", "any", "Maya needs help"],
    ["Maya", "", "Maya needs help"],
    ["", "algebra", "A student needs help with algebra"],
  ])("titles %p asking about %p as %p", (name, topic, title) => {
    expect(inviteAlertTitle(name, topic)).toBe(title);
  });
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

describe("an admin push", () => {
  test("goes to each token as a visible notification and sorts out the failures", async () => {
    mockSendEach.mockResolvedValue({
      successCount: 1,
      responses: [
        { success: true },
        { success: false, error: fcmError("messaging/registration-token-not-registered") },
        { success: false, error: fcmError("messaging/internal-error") },
      ],
    });

    const result = await sendAdminPush({ tokens: ["live", "gone", "flaky"], title: "Hi", body: "Hello" });

    const messages = mockSendEach.mock.calls[0][0];
    expect(messages.map((m: { token: string }) => m.token)).toEqual(["live", "gone", "flaky"]);
    expect(messages[0]).toMatchObject({
      notification: { title: "Hi", body: "Hello" },
      data: { type: "admin_message" },
      android: { notification: { channelId: "teacher_minute_updates", defaultSound: true } },
      apns: { payload: { aps: { sound: "default" } } },
    });
    expect(result).toEqual({ sent: 1, dead: ["gone"], failed: ["flaky"] });
  });

  test("sends a title alone, and custom data that cannot override the type", async () => {
    mockSendEach.mockResolvedValue({ successCount: 1, responses: [{ success: true }] });

    await sendAdminPush({ tokens: ["live"], title: "Hi", data: { screen: "minutes", type: "spoofed" } });

    const [message] = mockSendEach.mock.calls[0][0];
    expect(message.notification).toEqual({ title: "Hi" });
    expect(message.data).toEqual({ screen: "minutes", type: "admin_message" });
  });

  test("sends nothing when no one has a token", async () => {
    expect(await sendAdminPush({ tokens: [], title: "Hi", body: "Hello" })).toEqual({ sent: 0, dead: [], failed: [] });
    expect(mockSendEach).not.toHaveBeenCalled();
  });
});

describe("the student's pushes", () => {
  const DEFAULT_SOUND = {
    android: { notification: { channelId: "teacher_minute_updates", defaultSound: true } },
    apns: { payload: { aps: { sound: "default" } } },
  };

  test("a teacher found plays the default sound", async () => {
    mockSend.mockResolvedValue("message-id");
    await sendAcceptedPush({
      fcmToken: TOKEN,
      teacherName: "Anna",
      questionId: "question-1",
      agoraChannel: "",
      agoraToken: "",
      agoraUid: 0,
    });
    expect(mockSend.mock.calls[0][0]).toMatchObject(DEFAULT_SOUND);
  });

  test("no teacher available plays the default sound", async () => {
    mockSend.mockResolvedValue("message-id");
    await sendNoMatchPush({ fcmToken: TOKEN, questionId: "question-1" });
    expect(mockSend.mock.calls[0][0]).toMatchObject(DEFAULT_SOUND);
  });
});
