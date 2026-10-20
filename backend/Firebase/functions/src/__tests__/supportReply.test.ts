/**
 * Replying to a support ticket from the admin console: the mail that goes out
 * through the support SMTP account, and the record left on the ticket.
 */

const mockDocs = new Map<string, Record<string, any>>();
const mockSendMail = jest.fn();
const mockCreateTransport = jest.fn((_options: unknown) => ({ sendMail: mockSendMail }));

jest.mock("nodemailer", () => ({ createTransport: (o: unknown) => mockCreateTransport(o) }));

jest.mock("firebase-admin", () => {
  const doc = (id: string) => ({
    id,
    get: async () => ({ id, exists: mockDocs.has(id), data: () => mockDocs.get(id) }),
    update: async (patch: Record<string, any>) => {
      const current = mockDocs.get(id)!;
      for (const [k, v] of Object.entries(patch)) {
        current[k] = v?.kind === "array-union" ? [...(current[k] ?? []), ...v.values] : v;
      }
    },
  });
  const firestore = { collection: () => ({ doc }) };
  return { firestore: () => firestore, database: () => ({}), auth: () => ({}) };
});
jest.mock("firebase-admin/firestore", () => {
  class Timestamp {
    constructor(private ms: number) {}
    static now() { return new Timestamp(Date.now()); }
    toMillis() { return this.ms; }
  }
  return {
    Timestamp,
    FieldValue: { arrayUnion: (...values: unknown[]) => ({ kind: "array-union", values }) },
  };
});
jest.mock("firebase-functions", () => ({ logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() } }));
jest.mock("firebase-functions/v2/https", () => ({
  onCall: (a: unknown, b?: unknown) => b ?? a,
  HttpsError: class extends Error { constructor(public code: string, message: string) { super(message); } },
}));
jest.mock("../stats", () => ({}));
jest.mock("../presence", () => ({ ONLINE_TEACHERS_PATH: "onlineTeachers" }));
jest.mock("../pilot", () => ({ PILOT_COLLECTION: "pilotRegistrations" }));
jest.mock("../accountDeletion", () => ({}));
jest.mock("../presenceHistory", () => ({}));

import { adminRespondToContactRequest, supportReplySubject } from "../admin";

const respond = adminRespondToContactRequest as unknown as (req: unknown) => Promise<any>;
const ADMIN = { auth: { uid: "admin", token: { email: "yaronj3@gmail.com", email_verified: true, admin: true } } };
const NOW = Date.UTC(2026, 9, 20, 9, 0);

const SUPPORT_ENV = {
  SUPPORT_SMTP_HOST: "smtp-relay.brevo.com",
  SUPPORT_SMTP_PORT: "587",
  SUPPORT_SMTP_USER: "bda1be001@smtp-brevo.com",
  SUPPORT_SMTP_PASS: "secret",
  SUPPORT_SMTP_FROM: "Support <support@moreh-lerega.co.il>",
};

beforeEach(() => {
  mockDocs.clear();
  mockSendMail.mockReset().mockResolvedValue({ messageId: "<m1@brevo>" });
  mockCreateTransport.mockClear();
  Object.assign(process.env, SUPPORT_ENV);
  jest.spyOn(Date, "now").mockReturnValue(NOW);
  mockDocs.set("case-123", {
    id: "case-123",
    title: "Can't join\r\nBcc: x@evil.com",
    description: "The lesson won't start.\nPlease help.",
    userEmail: "dana@example.com",
    userName: "Dana",
    sentAt: "2026-10-19T08:00:00Z",
  });
});

afterEach(() => {
  jest.restoreAllMocks();
  for (const key of Object.keys(SUPPORT_ENV)) delete process.env[key];
});

describe("adminRespondToContactRequest", () => {
  test("sends from the support account with the case ID in the subject", async () => {
    await respond({ ...ADMIN, data: { requestId: "case-123", message: "  Try updating the app.  " } });

    expect(mockCreateTransport).toHaveBeenCalledWith({
      host: "smtp-relay.brevo.com",
      port: 587,
      auth: { user: "bda1be001@smtp-brevo.com", pass: "secret" },
    });
    const mail = mockSendMail.mock.calls[0][0];
    expect(mail.from).toBe("Support <support@moreh-lerega.co.il>");
    expect(mail.to).toBe("dana@example.com");
    expect(mail.subject).toBe("Re: Can't join Bcc: x@evil.com [Case #case-123]");
    expect(mail.text).toMatch(/^Try updating the app\.\n/);
    expect(mail.text).toContain("> The lesson won't start.\n> Please help.");
  });

  test("records the reply on the ticket after it is sent", async () => {
    const result = await respond({ ...ADMIN, data: { requestId: "case-123", message: "Fixed." } });

    const ticket = mockDocs.get("case-123")!;
    expect(ticket.responses).toHaveLength(1);
    expect(ticket.responses[0]).toMatchObject({
      to: "dana@example.com",
      from: "Support <support@moreh-lerega.co.il>",
      subject: supportReplySubject("case-123", ticket.title),
      message: "Fixed.",
      sentBy: "yaronj3@gmail.com",
      messageId: "<m1@brevo>",
    });
    expect(ticket.responses[0].sentAt.toMillis()).toBe(NOW);
    expect(ticket.lastRespondedAt.toMillis()).toBe(NOW);
    expect(result.response.sentAt).toBe(NOW);
  });

  test("records nothing when the send fails", async () => {
    mockSendMail.mockRejectedValue(new Error("535 auth failed"));
    await expect(respond({ ...ADMIN, data: { requestId: "case-123", message: "Hi" } }))
      .rejects.toMatchObject({ code: "internal" });
    expect(mockDocs.get("case-123")!.responses).toBeUndefined();
  });

  test("refuses to send without the support SMTP password", async () => {
    delete process.env.SUPPORT_SMTP_PASS;
    await expect(respond({ ...ADMIN, data: { requestId: "case-123", message: "Hi" } }))
      .rejects.toMatchObject({ code: "failed-precondition" });
    expect(mockSendMail).not.toHaveBeenCalled();
  });

  test("rejects an empty message, an unknown ticket, and a non-admin", async () => {
    await expect(respond({ ...ADMIN, data: { requestId: "case-123", message: "   " } }))
      .rejects.toMatchObject({ code: "invalid-argument" });
    await expect(respond({ ...ADMIN, data: { requestId: "nope", message: "Hi" } }))
      .rejects.toMatchObject({ code: "not-found" });
    await expect(respond({ auth: { uid: "x", token: { email: "x@y.com", email_verified: true } }, data: { requestId: "case-123", message: "Hi" } }))
      .rejects.toMatchObject({ code: "permission-denied" });
    expect(mockSendMail).not.toHaveBeenCalled();
  });
});
