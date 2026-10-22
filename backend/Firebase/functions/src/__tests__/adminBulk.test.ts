/**
 * The admin console's bulk actions: finding stale anonymous accounts, deleting
 * a selection, and emailing or pushing to a selection.
 */

const DAY = 24 * 3600 * 1000;
const NOW = Date.UTC(2026, 9, 17, 12);

type FakeUser = {
  uid: string;
  email?: string;
  phoneNumber?: string;
  providerData: { providerId: string }[];
  metadata: { creationTime: string; lastSignInTime?: string; lastRefreshTime?: string };
};

const mockUsers = new Map<string, FakeUser>();
const mockBalances = new Map<string, number>();
const mockDeleteAccountData = jest.fn();
const mockDeleteUser = jest.fn();
const mockSendMail = jest.fn();
const mockSendAdminPush = jest.fn();
const mockRtdb = new Map<string, unknown>();

jest.mock("firebase-admin", () => {
  const userDoc = (uid: string) => ({
    id: uid,
    get: async () => ({ id: uid, exists: mockBalances.has(uid), data: () => (mockBalances.has(uid) ? { remainingMinutes: mockBalances.get(uid) } : undefined) }),
  });
  const firestore = {
    collection: () => ({ doc: userDoc }),
    getAll: async (...refs: { get: () => Promise<unknown> }[]) => Promise.all(refs.map((r) => r.get())),
  };
  const auth = {
    listUsers: async (max: number, token?: string) => {
      const all = [...mockUsers.values()];
      const start = token ? Number(token) : 0;
      const next = start + max < all.length ? String(start + max) : undefined;
      return { users: all.slice(start, start + max), pageToken: next };
    },
    getUser: async (uid: string) => {
      const u = mockUsers.get(uid);
      if (!u) throw Object.assign(new Error("not found"), { code: "auth/user-not-found" });
      return u;
    },
    getUsers: async (ids: { uid: string }[]) => ({
      users: ids.map(({ uid }) => mockUsers.get(uid)).filter(Boolean),
    }),
    deleteUser: mockDeleteUser,
  };
  const database = {
    ref: (path: string) => ({ get: async () => ({ val: () => mockRtdb.get(path) ?? null }) }),
  };
  return { firestore: () => firestore, database: () => database, auth: () => auth };
});
jest.mock("firebase-admin/firestore", () => ({ Timestamp: class {}, FieldValue: {} }));
jest.mock("firebase-functions", () => ({ logger: { info: jest.fn(), warn: jest.fn() } }));
jest.mock("firebase-functions/v2/https", () => ({
  onCall: (a: unknown, b?: unknown) => b ?? a,
  HttpsError: class extends Error { constructor(public code: string, message: string) { super(message); } },
}));
jest.mock("../stats", () => ({}));
jest.mock("../presence", () => ({ ONLINE_TEACHERS_PATH: "onlineTeachers" }));
jest.mock("../pilot", () => ({ PILOT_COLLECTION: "pilotRegistrations" }));
jest.mock("../accountDeletion", () => ({ deleteAccountData: mockDeleteAccountData }));
jest.mock("../mailer", () => ({ sendMail: mockSendMail }));
jest.mock("../fcm", () => ({ sendAdminPush: mockSendAdminPush }));

import { adminFindInactiveAnonymous, adminBulkDeleteUsers, adminSendEmail, adminSendPush, adminListUsers } from "../admin";

const call = (fn: unknown, data: unknown, uid = "admin-uid") =>
  (fn as (req: unknown) => Promise<any>)({
    auth: { uid, token: { email: "yaronj3@gmail.com", email_verified: true, admin: true } },
    data,
  });

const iso = (ms: number) => new Date(ms).toUTCString();

function guest(uid: string, lastActiveDaysAgo: number): FakeUser {
  return {
    uid,
    providerData: [],
    metadata: { creationTime: iso(NOW - 30 * DAY), lastRefreshTime: iso(NOW - lastActiveDaysAgo * DAY) },
  };
}
function member(uid: string, lastActiveDaysAgo: number): FakeUser {
  return {
    uid,
    email: `${uid}@example.com`,
    providerData: [{ providerId: "password" }],
    metadata: { creationTime: iso(NOW - 30 * DAY), lastSignInTime: iso(NOW - lastActiveDaysAgo * DAY) },
  };
}

beforeEach(() => {
  jest.spyOn(Date, "now").mockReturnValue(NOW);
  mockUsers.clear();
  mockBalances.clear();
  mockDeleteAccountData.mockReset().mockResolvedValue(undefined);
  mockDeleteUser.mockReset().mockResolvedValue(undefined);
  mockSendMail.mockReset().mockResolvedValue(true);
  mockSendAdminPush.mockReset().mockImplementation(async ({ tokens }: { tokens: string[] }) => ({ sent: tokens.length, dead: [], failed: [] }));
  mockRtdb.clear();
  process.env.SMTP_HOST = "smtp.example.com";
});
afterEach(() => jest.restoreAllMocks());

const add = (...users: FakeUser[]) => users.forEach((u) => mockUsers.set(u.uid, u));

describe("adminFindInactiveAnonymous", () => {
  it("refuses a caller without admin rights", async () => {
    await expect(
      (adminFindInactiveAnonymous as any)({ auth: { uid: "x", token: { email: "x@example.com", email_verified: true } }, data: {} })
    ).rejects.toMatchObject({ code: "permission-denied" });
  });

  it("finds only anonymous accounts idle past the cutoff, oldest first", async () => {
    add(guest("g-fresh", 2), guest("g-old", 8), guest("g-older", 20), member("m-old", 60));
    const d = await call(adminFindInactiveAnonymous, {});
    expect(d.days).toBe(7);
    expect(d.scanned).toBe(4);
    expect(d.accounts.map((a: any) => a.uid)).toEqual(["g-older", "g-old"]);
  });

  it("judges activity by the latest token refresh, not just the sign-in", async () => {
    const u = guest("g", 1);
    u.metadata.lastSignInTime = iso(NOW - 25 * DAY);
    add(u);
    expect((await call(adminFindInactiveAnonymous, {})).accounts).toEqual([]);
  });

  it("keeps a guest who still holds minutes and counts them", async () => {
    add(guest("g-paid", 30), guest("g-empty", 30));
    mockBalances.set("g-paid", 15);
    mockBalances.set("g-empty", 0);
    const d = await call(adminFindInactiveAnonymous, {});
    expect(d.accounts.map((a: any) => a.uid)).toEqual(["g-empty"]);
    expect(d.skippedWithBalance).toBe(1);
  });

  it("pages through every account", async () => {
    for (let i = 0; i < 2500; i++) add(guest(`g${i}`, 10));
    const d = await call(adminFindInactiveAnonymous, { days: 7 });
    expect(d.scanned).toBe(2500);
    expect(d.accounts).toHaveLength(2500);
  });

  it("rejects a window under a day", async () => {
    await expect(call(adminFindInactiveAnonymous, { days: 0 })).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

describe("adminBulkDeleteUsers", () => {
  it("deletes each account's data before its auth record", async () => {
    add(member("a", 1), member("b", 1));
    const order: string[] = [];
    mockDeleteAccountData.mockImplementation(async (uid: string) => { order.push(`data:${uid}`); });
    mockDeleteUser.mockImplementation(async (uid: string) => { order.push(`auth:${uid}`); });
    const d = await call(adminBulkDeleteUsers, { uids: ["a", "b"] });
    expect(d.results).toEqual([{ uid: "a", status: "deleted" }, { uid: "b", status: "deleted" }]);
    expect(order).toEqual(["data:a", "auth:a", "data:b", "auth:b"]);
  });

  it("reports a failure per account and carries on", async () => {
    mockDeleteAccountData.mockImplementation(async (uid: string) => {
      if (uid === "busy") throw new Error("End your active lesson first.");
    });
    const d = await call(adminBulkDeleteUsers, { uids: ["busy", "ok"] });
    expect(d.results).toEqual([
      { uid: "busy", status: "failed", reason: "End your active lesson first." },
      { uid: "ok", status: "deleted" },
    ]);
    expect(mockDeleteUser).toHaveBeenCalledTimes(1);
  });

  it("never deletes the calling admin", async () => {
    const d = await call(adminBulkDeleteUsers, { uids: ["admin-uid", "x"] });
    expect(d.results[0]).toMatchObject({ uid: "admin-uid", status: "skipped" });
    expect(mockDeleteAccountData).toHaveBeenCalledTimes(1);
    expect(mockDeleteAccountData).toHaveBeenCalledWith("x");
  });

  it("caps a call at 20 accounts", async () => {
    const uids = Array.from({ length: 21 }, (_, i) => `u${i}`);
    await expect(call(adminBulkDeleteUsers, { uids })).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(call(adminBulkDeleteUsers, { uids: [] })).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("in cleanup mode, re-checks each account and spares any that changed", async () => {
    const linked = member("linked", 30); // signed up since the list was built
    add(guest("stale", 30), guest("back", 1), guest("paid", 30), linked);
    mockBalances.set("paid", 5);
    const d = await call(adminBulkDeleteUsers, {
      uids: ["stale", "back", "paid", "linked", "gone"],
      requireInactiveAnonymousDays: 7,
    });
    expect(d.results).toEqual([
      { uid: "stale", status: "deleted" },
      { uid: "back", status: "skipped", reason: "active again" },
      { uid: "paid", status: "skipped", reason: "holds minutes" },
      { uid: "linked", status: "skipped", reason: "no longer anonymous" },
      { uid: "gone", status: "skipped", reason: "already gone" },
    ]);
    expect(mockDeleteAccountData.mock.calls).toEqual([["stale"]]);
  });
});

describe("adminSendEmail", () => {
  it("sends each recipient their own message and counts the ones without email", async () => {
    add(member("a", 1), member("b", 1), guest("g", 1));
    const d = await call(adminSendEmail, { uids: ["a", "b", "g", "missing"], subject: " Hi ", text: " Hello " });
    expect(mockSendMail.mock.calls).toEqual([
      [{ to: "a@example.com", subject: "Hi", text: "Hello" }],
      [{ to: "b@example.com", subject: "Hi", text: "Hello" }],
    ]);
    expect(d).toEqual({ sent: 2, failed: [], withoutEmail: 1, notFound: 1 });
  });

  it("reports addresses that failed without stopping", async () => {
    add(member("a", 1), member("b", 1));
    mockSendMail.mockImplementation(async ({ to }: { to: string }) => {
      if (to === "a@example.com") throw new Error("mailbox full");
      return true;
    });
    const d = await call(adminSendEmail, { uids: ["a", "b"], subject: "s", text: "t" });
    expect(d).toMatchObject({ sent: 1, failed: ["a@example.com"] });
  });

  it("refuses when SMTP is not configured rather than pretending to send", async () => {
    delete process.env.SMTP_HOST;
    add(member("a", 1));
    await expect(call(adminSendEmail, { uids: ["a"], subject: "s", text: "t" })).rejects.toMatchObject({ code: "failed-precondition" });
    expect(mockSendMail).not.toHaveBeenCalled();
  });

  it("requires a subject and a message", async () => {
    await expect(call(adminSendEmail, { uids: ["a"], subject: " ", text: "t" })).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(call(adminSendEmail, { uids: ["a"], subject: "s", text: "" })).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

describe("adminSendPush", () => {
  it("pushes to every device of each user once, and counts users without a token", async () => {
    mockRtdb.set("users/a/fcmToken", "tok-a-phone");
    mockRtdb.set("users/a/devices", { "ios-1": { fcmToken: "tok-a-phone" }, "ios-2": { fcmToken: "tok-a-tablet" } });
    mockRtdb.set("users/b/devices", { "android-1": { fcmToken: "tok-b" } });

    const d = await call(adminSendPush, { uids: ["a", "b", "c", "a"], title: " New teachers ", body: " Come and ask " });

    expect(mockSendAdminPush).toHaveBeenCalledTimes(1);
    const { tokens, title, body } = mockSendAdminPush.mock.calls[0][0];
    expect([...tokens].sort()).toEqual(["tok-a-phone", "tok-a-tablet", "tok-b"]);
    expect({ title, body }).toEqual({ title: "New teachers", body: "Come and ask" });
    expect(d).toEqual({ reached: 2, withoutToken: 1, unreachable: 0, devicesSent: 3, devicesFailed: 0 });
  });

  it("counts a user reached when any one of their devices took it", async () => {
    mockRtdb.set("users/a/devices", { one: { fcmToken: "dead-a" }, two: { fcmToken: "live-a" } });
    mockRtdb.set("users/b/fcmToken", "dead-b");
    mockSendAdminPush.mockResolvedValue({ sent: 1, dead: ["dead-a"], failed: ["dead-b"] });

    const d = await call(adminSendPush, { uids: ["a", "b"], title: "t", body: "b" });

    expect(d).toEqual({ reached: 1, withoutToken: 0, unreachable: 1, devicesSent: 1, devicesFailed: 2 });
  });

  it("refuses a caller without admin rights", async () => {
    await expect(
      (adminSendPush as unknown as (r: unknown) => Promise<unknown>)({
        auth: { uid: "x", token: { email: "x@example.com", email_verified: true } },
        data: { uids: ["a"], title: "t", body: "b" },
      })
    ).rejects.toMatchObject({ code: "permission-denied" });
    expect(mockSendAdminPush).not.toHaveBeenCalled();
  });

  it("requires a title and a message within the limits", async () => {
    for (const data of [
      { uids: ["a"], title: " ", body: "b" },
      { uids: ["a"], title: "t", body: "" },
      { uids: ["a"], title: "t".repeat(101), body: "b" },
      { uids: ["a"], title: "t", body: "b".repeat(501) },
      { uids: [], title: "t", body: "b" },
      { uids: Array.from({ length: 101 }, (_, i) => `u${i}`), title: "t", body: "b" },
    ]) {
      await expect(call(adminSendPush, data)).rejects.toMatchObject({ code: "invalid-argument" });
    }
    expect(mockSendAdminPush).not.toHaveBeenCalled();
  });
});

describe("adminListUsers activity", () => {
  it("reports the last token refresh as last activity, with the sign-in beside it", async () => {
    const u = member("m", 30);
    u.metadata.lastRefreshTime = iso(NOW - 2 * 3600 * 1000);
    add(u);
    const d = await call(adminListUsers, {});
    expect(d.users[0].lastSignIn).toBe(Date.parse(iso(NOW - 30 * DAY)));
    expect(d.users[0].lastActiveAt).toBe(Date.parse(iso(NOW - 2 * 3600 * 1000)));
  });
});

describe("adminListUsers page size", () => {
  it("serves up to 1000 users a page when asked, 100 by default", async () => {
    for (let i = 0; i < 1200; i++) add(member(`m${i}`, 1));
    expect((await call(adminListUsers, {})).users).toHaveLength(100);
    const big = await call(adminListUsers, { limit: 5000 });
    expect(big.users).toHaveLength(1000);
    expect(big.nextPageToken).toBe("1000");
    expect((await call(adminListUsers, { limit: 1000, pageToken: big.nextPageToken })).users).toHaveLength(200);
  });
});
