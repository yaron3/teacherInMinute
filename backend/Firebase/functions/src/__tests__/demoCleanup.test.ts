/**
 * The admin console's purchase windows and the demo-data cleanup's rules for
 * what may be deleted.
 */

const mockDocs = new Map<string, Record<string, unknown>>();
const mockDeleted: string[] = [];
const mockQuestionDeletes: string[] = [];
const mockFileDeletes: string[] = [];

jest.mock("firebase-admin", () => {
  const docRef = (collection: string, id: string) => ({
    id,
    path: `${collection}/${id}`,
    get: async () => ({ exists: mockDocs.has(`${collection}/${id}`), data: () => mockDocs.get(`${collection}/${id}`) }),
  });
  const firestore = {
    collection: (c: string) => ({ doc: (id: string) => docRef(c, id) }),
    recursiveDelete: async (ref: { path: string }) => { mockDeleted.push(ref.path); },
  };
  const storage = { bucket: () => ({ file: (p: string) => ({ delete: async () => { mockFileDeletes.push(p); } }) }) };
  return { firestore: () => firestore, storage: () => storage, auth: () => ({}) };
});
jest.mock("../accountDeletion", () => ({
  deleteQuestionRecords: async (ref: { path: string }) => { mockQuestionDeletes.push(ref.path); },
}));

import { summarizePurchases, PurchaseRow, purchaseMethod } from "../purchaseStats";
import { blockReason, deleteDemoCleanupItem, describe as describeItem } from "../demoCleanup";

const HOUR = 3600 * 1000;
const DAY = 24 * HOUR;
const NOW = Date.UTC(2026, 10, 27, 12);

function row(p: Partial<PurchaseRow>): PurchaseRow {
  return {
    uid: "u1", status: "completed", currency: "ILS", priceCents: 12000, minutes: 60, method: "paypal",
    createdAtMs: NOW - HOUR, completedAtMs: NOW - HOUR, ...p,
  };
}

describe("summarizePurchases", () => {
  it("buckets completed purchases into rolling 24h, 7 and 30 day windows by completion time", () => {
    const s = summarizePurchases([
      row({ uid: "a", completedAtMs: NOW - 2 * HOUR }),
      row({ uid: "b", completedAtMs: NOW - 3 * DAY, method: "card" }),
      row({ uid: "c", completedAtMs: NOW - 20 * DAY }),
      row({ uid: "d", completedAtMs: NOW - 40 * DAY }),
    ], NOW, new Set());
    expect([s.day.count, s.week.count, s.month.count]).toEqual([1, 2, 3]);
    expect(s.week.byMethod).toEqual({ paypal: 1, card: 1 });
    expect(s.month.minutes).toBe(180);
  });

  it("keeps revenue per currency and counts distinct buyers", () => {
    const s = summarizePurchases([
      row({ uid: "a" }), row({ uid: "a", priceCents: 1 }), row({ uid: "b", currency: "USD", priceCents: 500 }),
    ], NOW, new Set());
    expect(s.day.byCurrency).toEqual({ ILS: 12001, USD: 500 });
    expect(s.day.buyers).toBe(2);
  });

  it("leaves demo users out and counts unpaid checkouts opened in the window as abandoned", () => {
    const s = summarizePurchases([
      row({ uid: "demo" }),
      row({ uid: "a", status: "paypal_created", completedAtMs: null }),
      row({ uid: "a", status: "cancelled", completedAtMs: null, createdAtMs: NOW - 2 * DAY }),
    ], NOW, new Set(["demo"]));
    expect(s.day.count).toBe(0);
    expect([s.day.abandoned, s.week.abandoned]).toEqual([1, 2]);
  });

  it("falls back to the opening time when a completed purchase has no completion time", () => {
    expect(summarizePurchases([row({ completedAtMs: null })], NOW, new Set()).day.count).toBe(1);
  });

  it("names the method from the checkout", () => {
    expect(purchaseMethod({ paymentMethod: "apple_pay" })).toBe("apple_pay");
    expect(purchaseMethod({ paypalOrderId: "X" })).toBe("paypal");
    expect(purchaseMethod({ tranzilaTransactionId: "1" })).toBe("card");
  });
});

describe("blockReason", () => {
  const demo = new Set(["ds", "dt"]);

  it("allows a record whose every party is a demo user", () => {
    expect(blockReason("question", { studentUid: "ds", acceptedByTeacher: "dt", status: "completed" }, demo)).toBeNull();
    expect(blockReason("purchase", { uid: "ds", status: "completed" }, demo)).toBeNull();
  });

  it("refuses a question a demo student asked a real teacher, which holds that teacher's earnings", () => {
    expect(blockReason("question", { studentUid: "ds", acceptedByTeacher: "real", status: "completed" }, demo))
      .toBe("involves a real user");
    expect(blockReason("lesson", { studentUid: "real", teacherUid: "dt", status: "completed" }, demo))
      .toBe("involves a real user");
  });

  it("refuses live questions and lessons", () => {
    expect(blockReason("question", { studentUid: "ds", status: "searching" }, demo)).toBe("live (searching)");
    expect(blockReason("lesson", { studentUid: "ds", teacherUid: "dt", status: "in_progress" }, demo)).toBe("live (in_progress)");
  });

  it("refuses a real user's record", () => {
    expect(blockReason("purchase", { uid: "real", status: "completed" }, demo)).toBe("not a demo user's");
    expect(blockReason("contact", {}, demo)).toBe("names no user");
  });

  it("allows a sample support request whoever sent it", () => {
    expect(blockReason("contact", { userId: "real", sample: true }, demo)).toBeNull();
  });
});

describe("deleteDemoCleanupItem", () => {
  beforeEach(() => {
    mockDocs.clear();
    mockDeleted.length = 0;
    mockQuestionDeletes.length = 0;
    mockFileDeletes.length = 0;
  });
  const demo = new Set(["ds", "dt"]);

  it("re-checks on the server and skips a record that now involves a real user", async () => {
    mockDocs.set("questions/q1", { studentUid: "ds", acceptedByTeacher: "real", status: "completed" });
    expect(await deleteDemoCleanupItem({ kind: "question", id: "q1" }, demo)).toEqual({ status: "skipped", reason: "involves a real user" });
    expect(mockQuestionDeletes).toEqual([]);
  });

  it("skips a record that is already gone", async () => {
    expect(await deleteDemoCleanupItem({ kind: "purchase", id: "gone" }, demo)).toEqual({ status: "skipped", reason: "already gone" });
  });

  it("deletes a question with its side data, and a contact request with its attachments", async () => {
    mockDocs.set("questions/q2", { studentUid: "ds", status: "completed" });
    mockDocs.set("contactRequests/c1", { userId: "ds", id: "c1", attachmentCount: 2 });
    expect((await deleteDemoCleanupItem({ kind: "question", id: "q2" }, demo)).status).toBe("deleted");
    expect((await deleteDemoCleanupItem({ kind: "contact", id: "c1" }, demo)).status).toBe("deleted");
    expect(mockQuestionDeletes).toEqual(["questions/q2"]);
    expect(mockFileDeletes).toEqual(["contactAttachments/ds/c1/0.jpg", "contactAttachments/ds/c1/1.jpg"]);
    expect(mockDeleted).toEqual(["contactRequests/c1"]);
  });
});

describe("describe", () => {
  it("summarizes a purchase in one line", () => {
    expect(describeItem("purchase", { priceCents: 1, currency: "ILS", minutes: 1, paymentMethod: "paypal", status: "completed" }).summary)
      .toBe("0.01 ILS · 1 min · paypal · completed");
  });
});
