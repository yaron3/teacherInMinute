import { readFileSync } from "fs";
import { resolve } from "path";
import { JSDOM } from "jsdom";

/**
 * UI tests for the admin console (backend/Firebase/admin.html).
 *
 * The page runs in jsdom with its inline script and inline `onclick`
 * handlers live, so rows are clicked the way an admin clicks them. The
 * Firebase SDK is a fake: each callable is answered from `responses`, and
 * every call is recorded in `calls`.
 */

const HTML = readFileSync(resolve(__dirname, "../../../admin.html"), "utf8")
  // The SDK <script src> tags would never load in jsdom; the fake replaces them.
  .replace(/<script src="[^"]*"><\/script>/g, "");

type Responder = (data: any) => any;

function openConsole(responses: Record<string, Responder | object> = {}, url = "http://localhost:8080/admin.html") {
  const calls: { name: string; data: any }[] = [];
  let authCallback: (user: unknown) => void = () => undefined;
  const confirm = jest.fn(() => true);

  const dom = new JSDOM(HTML, {
    url,
    runScripts: "dangerously",
    pretendToBeVisual: true,
    beforeParse(window: any) {
      window.confirm = confirm;
      window.firebase = {
        initializeApp: () => undefined,
        auth: Object.assign(
          () => ({
            onAuthStateChanged: (cb: (user: unknown) => void) => { authCallback = cb; },
            signInWithEmailAndPassword: jest.fn(),
            signInWithPopup: jest.fn(),
            signOut: jest.fn(async () => authCallback(null)),
          }),
          { GoogleAuthProvider: class {} }
        ),
        functions: () => ({
          httpsCallable: (name: string) => async (data: any) => {
            calls.push({ name, data });
            const r = responses[name];
            if (r === undefined) return { data: { success: true } };
            const value = typeof r === "function" ? await (r as Responder)(data) : r;
            return { data: value };
          },
        }),
      };
    },
  });

  const window = dom.window as any;
  const document = window.document as Document;
  const $ = (sel: string) => document.querySelector(sel) as HTMLElement;
  const $$ = (sel: string) => [...document.querySelectorAll(sel)] as HTMLElement[];
  /** Lets the awaited fake callables and the renders after them finish. */
  const settle = () => new Promise((r) => setTimeout(r, 0));

  return {
    window, document, $, $$, calls, confirm, settle,
    callsTo: (name: string) => calls.filter((c) => c.name === name),
    signIn: async () => { authCallback({ uid: "admin", email: "admin@example.com" }); await settle(); },
    nav: async (label: string) => {
      $$(".nav-item").find((n) => n.textContent!.includes(label))!.click();
      await settle();
    },
    button: (scope: string, label: string) =>
      $$(`${scope} button`).find((b) => b.textContent!.trim() === label)!,
    close: () => window.close(),
  };
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

/** A name that breaks out of a quoted onclick argument, an attribute, or both. */
const EVIL = `x');window.__pwned=1;//"><img src=x onerror="window.__pwned=2">`;

function dashboard(overrides: any = {}) {
  return {
    pendingVerifications: 2,
    teachers: { total: 5, online: 0, list: [], staleProjections: 0 },
    questions: {
      searching: 0, accepted: 0, inProgress: 0, completed: 7, unanswered: 1, cancelled: 2,
      rtdbActive: 0, rtdbList: [], oldestSearching: null,
    },
    lessons: { active: [] },
    users: { total: 42 },
    platform: { registeredTeacherCount: 5, averageConnectSeconds: 12, connectedQuestionCount: 3 },
    revenue: {
      totalCents: 5000, currency: "ILS", byCurrency: { ILS: 5000, USD: 1999 },
      completedPayments: 3, avgPaymentCents: 2500, maxPaymentCents: 3000, maxPaymentId: "p1",
    },
    ...overrides,
  };
}

function user(overrides: any = {}) {
  return {
    uid: "uid-1", email: "dana@example.com", displayName: "Dana", photoURL: null,
    disabled: false, role: "student", remainingMinutes: 30, totalMinutes: 60,
    createdAt: Date.UTC(2026, 0, 1), lastSignIn: Date.now(), hasProfile: true,
    ...overrides,
  };
}

let page: ReturnType<typeof openConsole> | undefined;
afterEach(() => { page?.close(); page = undefined; });

// ── Sign-in and overview ──────────────────────────────────────────────────────

describe("sign-in", () => {
  it("shows only the login card until a user is signed in", async () => {
    page = openConsole({ adminDashboardStatus: dashboard() });
    expect(page.$("#login-screen").style.display).not.toBe("none");
    expect(page.$("#app").style.display).not.toBe("flex");
    expect(page.calls).toHaveLength(0);

    await page.signIn();
    expect(page.$("#login-screen").style.display).toBe("none");
    expect(page.$("#app").style.display).toBe("flex");
    expect(page.callsTo("adminDashboardStatus")).toHaveLength(1);
  });

  it("offers Google sign-in only — no email and password form", () => {
    page = openConsole();
    expect(page.$("#google-login").style.display).not.toBe("none");
    expect(page.$("#login-screen input[type=password]")).toBeNull();
    expect(page.$("#login-screen input[type=email]")).toBeNull();
    expect(page.$("#file-notice").style.display).toBe("none");
    expect(page.$(".login-card").classList.contains("wide")).toBe(false);
  });

  it("opened from disk, explains how to serve it instead of offering sign-in", () => {
    page = openConsole({}, "file:///Users/me/My%20Code/backend/Firebase/admin.html");
    expect(page.$("#file-notice").style.display).toBe("block");
    expect(page.$("#google-login").style.display).toBe("none");
    expect(page.$(".login-card").classList.contains("wide")).toBe(true);
    expect(page.$("#file-notice-command").textContent)
      .toBe('python3 -m http.server 8080 --directory "/Users/me/My Code/backend/Firebase"');
    expect(page.$("#file-notice-link").getAttribute("href")).toBe("http://localhost:8080/admin.html");
  });

  it("goes back to the login card on sign-out", async () => {
    page = openConsole({ adminDashboardStatus: dashboard() });
    await page.signIn();
    page.$(".nav-signout").click();
    await page.settle();
    expect(page.$("#login-screen").style.display).toBe("flex");
    expect(page.$("#app").style.display).toBe("none");
  });
});

describe("overview", () => {
  it("renders the stat cards and the pending-verification badge", async () => {
    page = openConsole({ adminDashboardStatus: dashboard() });
    await page.signIn();
    const stats = page.$("#overview-stats").textContent!;
    expect(stats).toContain("42");
    expect(stats).toContain("12s");
    expect(page.$("#verify-badge").textContent).toBe("2");
    expect(page.$("#verify-badge").style.display).not.toBe("none");
  });

  it("summarises the live queue and the last 24 hours", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard({
        teachers: { total: 5, online: 3, list: [], staleProjections: 0 },
        questions: { ...dashboard().questions, searching: 4 },
        lastDay: {
          questions: { asked: 10, notAnswered: 3, timedOut: 2, cancelledWaiting: 1, answered: 6, avgWaitSeconds: 75 },
          teachers: { avgOnline: 2.46, avgDistinctPerHour: 4, hoursCovered: 6 },
        },
      }),
    });
    await page.signIn();
    const card = (label: string) => page!.$$("#overview-summary .stat-card")
      .find((c) => c.textContent!.includes(label))!;
    expect(card("Online Teachers").querySelector(".stat-value")!.textContent).toBe("3");
    expect(card("Waiting for an Answer").querySelector(".stat-value")!.textContent).toBe("4");
    expect(card("Avg Teachers Online / Hour").querySelector(".stat-value")!.textContent).toBe("2.5");
    expect(card("Avg Teachers Online / Hour").textContent).toContain("6h of data");
    expect(card("Not Answered (24h)").querySelector(".stat-value")!.textContent).toBe("3");
    expect(card("Avg Wait to Answer (24h)").querySelector(".stat-value")!.textContent).toBe("1m 15s");
  });

  it("shows dashes in the 24-hour summary when there is no data yet", async () => {
    page = openConsole({ adminDashboardStatus: dashboard() });
    await page.signIn();
    const summary = page.$("#overview-summary").textContent!;
    expect(summary).toContain("Avg Teachers Online / Hour");
    expect(summary).toContain("0h of data");
    expect(summary).not.toContain("undefined");
  });

  it("shows revenue per currency instead of adding shekels to dollars", async () => {
    page = openConsole({ adminDashboardStatus: dashboard() });
    await page.signIn();
    const revenue = page.$$("#overview-stats .stat-card")
      .find((c) => c.textContent!.includes("Total Revenue"))!.textContent!;
    expect(revenue).toMatch(/₪\s?50\.00/);
    expect(revenue).toContain("$19.99");
    expect(revenue).not.toContain("69.99");
  });

  it("flags an out-of-sync teacher and takes them offline on request", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard({
        teachers: {
          total: 1, online: 1, staleProjections: 1,
          list: [{ uid: "t-1", displayName: EVIL, subjects: ["math"], stale: true, published: true, verified: true }],
        },
      }),
    });
    await page.signIn();
    expect(page.$("#online-teachers-table").textContent).toContain("published, not online");

    page.button("#online-teachers-table", "Go offline").click();
    await page.settle();
    expect(page.confirm).toHaveBeenCalledWith(expect.stringContaining(EVIL));
    expect(page.callsTo("adminMutateUser")).toEqual([
      { name: "adminMutateUser", data: { action: "goOffline", uid: "t-1" } },
    ]);
    expect(page.window.__pwned).toBeUndefined();
  });
});

// ── Users ─────────────────────────────────────────────────────────────────────

describe("users", () => {
  async function usersPage(users: any[]) {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: { users, nextPageToken: null },
    });
    await page.signIn();
    await page.nav("Users");
    return page;
  }

  it("splits students and teachers into their own tables and marks missing profiles", async () => {
    const p = await usersPage([
      user(),
      user({ uid: "uid-3", email: "guest@example.com", role: null, anonymous: true }),
      user({ uid: "uid-2", email: "yossi@example.com", displayName: "Yossi", role: "teacher", totalMinutes: 90, hasProfile: false }),
    ]);
    const students = p.$$("#students-table tr");
    expect(students.map((r) => r.dataset.id)).toEqual(["uid-1", "uid-3"]);
    expect(students[0].textContent).toContain("dana@example.com");
    expect(students[0].textContent).not.toContain("no profile doc");
    expect(students[1].textContent).toContain("guest");
    expect(p.$("#students-count").textContent).toBe("(2)");

    const teachers = p.$$("#teachers-table tr");
    expect(teachers.map((r) => r.dataset.id)).toEqual(["uid-2"]);
    expect(teachers[0].textContent).toContain("90");
    expect(teachers[0].textContent).toContain("no profile doc");
    expect(p.$("#teachers-count").textContent).toBe("(1)");
    // A teacher has no minutes balance to adjust.
    expect(p.$$("#teachers-table button").map((b) => b.textContent)).not.toContain("± Min");
  });

  it("filters both tables by the one search box", async () => {
    const p = await usersPage([
      user(),
      user({ uid: "uid-2", email: "yossi@example.com", displayName: "Yossi", role: "teacher" }),
      user({ uid: "uid-4", email: "yael@example.com", displayName: "Yael", role: "teacher" }),
    ]);
    const search = p.$("#user-search") as HTMLInputElement;
    search.value = "yossi";
    search.dispatchEvent(new p.window.Event("input"));
    expect(p.$("#students-table").textContent).toContain("No students found");
    expect(p.$$("#teachers-table tr").map((r) => r.dataset.id)).toEqual(["uid-2"]);
    expect(p.$("#teachers-count").textContent).toBe("(1 of 2)");
  });

  it("filters the loaded users by search text", async () => {
    const p = await usersPage([user(), user({ uid: "uid-2", email: "yossi@example.com", displayName: "Yossi" })]);
    const search = p.$("#user-search") as HTMLInputElement;
    search.value = "yos";
    search.dispatchEvent(new p.window.Event("input"));
    expect(p.$$("#students-table tr")).toHaveLength(1);
    expect(p.$("#students-table").textContent).toContain("Yossi");
  });

  it("passes a hostile name and UID to every row action as plain text", async () => {
    const uid = `u'1"<b>`;
    const p = await usersPage([user({ uid, email: EVIL, displayName: EVIL })]);
    expect(p.$("#students-table b")).toBeNull();
    expect(p.$("#students-table img")).toBeNull();

    p.button("#students-table", "✉").click();
    expect(p.$("#msg-teacher-label").textContent).toBe(EVIL);

    p.button("#students-table", "Delete").click();
    await p.settle();
    expect(p.confirm).toHaveBeenCalledWith(expect.stringContaining(EVIL));
    expect(p.callsTo("adminMutateUser")).toEqual([
      { name: "adminMutateUser", data: { action: "delete", uid } },
    ]);
    expect(p.window.__pwned).toBeUndefined();
  });

  it("never turns a javascript: photo URL into an image source", async () => {
    const p = await usersPage([user({ photoURL: "javascript:window.__pwned=3" })]);
    expect(p.$("#students-table img").getAttribute("src")).toBe("about:blank");
  });

  it("keeps an https photo URL, query string included", async () => {
    const p = await usersPage([user({ photoURL: "https://cdn.example.com/a.png?x=1&y=2" })]);
    expect(p.$("#students-table img").getAttribute("src")).toBe("https://cdn.example.com/a.png?x=1&y=2");
  });

  it("asks before disabling and does nothing if the admin cancels", async () => {
    const p = await usersPage([user()]);
    p.confirm.mockReturnValueOnce(false);
    p.button("#students-table", "Disable").click();
    await p.settle();
    expect(p.confirm).toHaveBeenCalledWith(expect.stringContaining("takes them offline"));
    expect(p.callsTo("adminMutateUser")).toHaveLength(0);

    p.button("#students-table", "Disable").click();
    await p.settle();
    expect(p.callsTo("adminMutateUser")).toEqual([
      { name: "adminMutateUser", data: { action: "disable", uid: "uid-1" } },
    ]);
  });

  it("enables a disabled user without asking", async () => {
    const p = await usersPage([user({ disabled: true })]);
    p.button("#students-table", "Enable").click();
    await p.settle();
    expect(p.confirm).not.toHaveBeenCalled();
    expect(p.callsTo("adminMutateUser")[0].data).toEqual({ action: "enable", uid: "uid-1" });
  });

  it("adjusts minutes by the entered delta", async () => {
    const p = await usersPage([user()]);
    p.button("#students-table", "± Min").click();
    expect(p.$("#adjust-modal").classList.contains("open")).toBe(true);
    (p.$("#adjust-delta") as HTMLInputElement).value = "-15";
    p.button("#adjust-modal", "Apply").click();
    await p.settle();
    expect(p.callsTo("adminMutateUser")[0].data).toEqual({ action: "adjustMinutes", uid: "uid-1", delta: -15 });
    expect(p.$("#adjust-modal").classList.contains("open")).toBe(false);
  });

  it("shows a hostile name safely in the user detail modal", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: { users: [user({ displayName: EVIL })], nextPageToken: null },
      adminGetUserDetail: {
        auth: { uid: "uid-1", email: "dana@example.com", providers: ["password"] },
        firestore: { fullName: EVIL, role: "teacher", subjectSelections: { [EVIL]: [EVIL] } },
        teacherDoc: null, purchases: [], questions: [], taughtQuestions: [], ratings: [],
        messages: [], presence: { status: "online", subjects: [] }, onlineEntry: null,
      },
    });
    await page.signIn();
    await page.nav("Users");
    page.button("#students-table", "View").click();
    await page.settle();

    expect(page.$("#user-modal-title").textContent).toBe(EVIL);
    expect(page.$("#user-modal-body img")).toBeNull();
    page.button("#user-modal-body", "Go offline").click();
    await page.settle();
    expect(page.callsTo("adminMutateUser")[0].data).toEqual({ action: "goOffline", uid: "uid-1" });
    expect(page.window.__pwned).toBeUndefined();
  });
});

// ── Questions ─────────────────────────────────────────────────────────────────

describe("questions", () => {
  it("keeps question text inside the tooltip and blocks javascript: photo links", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListQuestions: {
        hasMore: false,
        questions: [{
          id: "question-123456", topic: "math", status: "completed", createdAt: Date.now(),
          text: `" onmouseover="window.__pwned=4`, studentUid: "s-1", studentName: "Dana",
          durationSeconds: 125, costCents: 1250, teacherEarningsCents: 900, currency: "ILS",
          photoUrls: ["javascript:window.__pwned=5", "https://example.com/p.jpg"],
        }],
      },
    });
    await page.signIn();
    await page.nav("Questions");

    const cell = page.$("#questions-table td.td-mono");
    expect(cell.getAttribute("title")).toBe(`" onmouseover="window.__pwned=4`);
    expect(cell.hasAttribute("onmouseover")).toBe(false);
    const links = page.$$("#questions-table a").map((a) => a.getAttribute("href"));
    expect(links).toEqual(["about:blank", "https://example.com/p.jpg"]);
    expect(page.$("#questions-table").textContent).toContain("2m 5s");
    expect(page.$("#questions-table").textContent).toMatch(/₪\s?12\.50/);
  });

  it("requests the chosen status filter", async () => {
    page = openConsole({ adminDashboardStatus: dashboard(), adminListQuestions: { questions: [], hasMore: false } });
    await page.signIn();
    await page.nav("Questions");
    page.$$("#q-filter-tabs .filter-tab").find((t) => t.textContent === "Unanswered")!.click();
    await page.settle();
    expect(page.callsTo("adminListQuestions").at(-1)!.data).toMatchObject({ status: "unanswered" });
  });
});

// ── Payments ──────────────────────────────────────────────────────────────────

describe("payments", () => {
  it("totals completed payments per currency", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListPayments: {
        payments: [
          { id: "pay-1", status: "completed", priceCents: 5000, currency: "ILS", createdAt: Date.now() },
          { id: "pay-2", status: "completed", priceCents: 1999, currency: "USD", createdAt: Date.now() },
          { id: "pay-3", status: "completed", priceCents: 1000, currency: "ILS", createdAt: Date.now() },
          { id: "pay-4", status: "cancelled", priceCents: 9999, currency: "USD", createdAt: Date.now() },
        ],
      },
    });
    await page.signIn();
    await page.nav("Payments");

    const stats = page.$("#payment-stats").textContent!;
    expect(stats).toContain("3");
    expect(stats).toMatch(/₪\s?60\.00/);
    expect(stats).toContain("$19.99");
    expect(stats).not.toContain("99.99");
    expect(stats).toContain("4 rows shown");
    expect(page.$$("#payments-table tr")).toHaveLength(4);
  });

  it("hides the totals when a non-completed filter is chosen", async () => {
    page = openConsole({ adminDashboardStatus: dashboard(), adminListPayments: { payments: [] } });
    await page.signIn();
    await page.nav("Payments");
    page.$$("#page-payments .filter-tab").find((t) => t.textContent === "Cancelled")!.click();
    await page.settle();
    expect(page.callsTo("adminListPayments").at(-1)!.data).toMatchObject({ statusFilter: "cancelled" });
    expect(page.$("#payment-stats").style.display).toBe("none");
  });
});

// ── Coupons ───────────────────────────────────────────────────────────────────

describe("coupons", () => {
  it("refuses to create a coupon without the required fields", async () => {
    page = openConsole({ adminDashboardStatus: dashboard(), adminListCoupons: { coupons: [] } });
    await page.signIn();
    await page.nav("Coupons");
    page.button("#page-coupons", "+ Create Coupon").click();
    page.button("#coupon-modal", "Create").click();
    await page.settle();
    expect(page.callsTo("adminCreateCoupon")).toHaveLength(0);
    expect(page.$("#toast").textContent).toContain("Fill all required fields");
  });

  it("creates a coupon with an upper-cased custom code", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListCoupons: { coupons: [] },
      adminCreateCoupon: { success: true, couponId: "WELCOME50", appliedDirectly: false },
    });
    await page.signIn();
    await page.nav("Coupons");
    page.button("#page-coupons", "+ Create Coupon").click();
    (page.$("#c-uid") as HTMLInputElement).value = "student-1";
    (page.$("#c-by") as HTMLInputElement).value = "Yaron";
    (page.$("#c-code") as HTMLInputElement).value = "welcome50";
    page.button("#coupon-modal", "Create").click();
    await page.settle();
    expect(page.callsTo("adminCreateCoupon")[0].data).toEqual({
      studentUserId: "student-1", numberOfMinutes: 60, price: 9.99, createdBy: "Yaron",
      couponId: "WELCOME50", applyDirectly: false,
    });
  });
});

// ── Verify teachers ───────────────────────────────────────────────────────────

describe("verify teachers", () => {
  it("verifies a teacher with a hostile name and removes their card", async () => {
    const uid = `t'9"`;
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListPendingTeachers: {
        teachers: [
          { uid, displayName: EVIL, email: "t@example.com", uploadedDocuments: ["selfie_1", "credentials_1"], subjectSelections: {} },
          { uid: "t-2", displayName: "Second", email: "s@example.com", uploadedDocuments: ["selfie_2"], subjectSelections: {} },
        ],
      },
      adminGetTeacherDocs: { docs: [
        { name: "selfie_1", url: "https://storage.example.com/s.jpg" },
        { name: "credentials_1", url: "javascript:window.__pwned=6" },
      ] },
    });
    await page.signIn();
    await page.nav("Verify Teachers");
    expect(page.$$(".teacher-card")).toHaveLength(2);
    expect(page.$("#verify-badge").textContent).toBe("2");

    page.button(".teacher-card", "🖼 Load Document Previews").click();
    await page.settle();
    expect(page.callsTo("adminGetTeacherDocs")[0].data).toEqual({ uid });
    expect(page.$$(".teacher-card .doc-img").map((i) => i.getAttribute("src")))
      .toEqual(["https://storage.example.com/s.jpg", "about:blank"]);

    page.button(".teacher-card", "✓ Verify Teacher").click();
    await page.settle();
    expect(page.confirm).toHaveBeenCalledWith(expect.stringContaining(EVIL));
    expect(page.callsTo("adminVerifyTeacher")[0].data).toEqual({ uid, verified: true });
    expect(page.$$(".teacher-card")).toHaveLength(1);
    expect(page.$("#verify-badge").textContent).toBe("1");
    expect(page.window.__pwned).toBeUndefined();
  });

  it("sends a message from a teacher card", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListPendingTeachers: { teachers: [
        { uid: "t-1", displayName: "Noa", email: "n@example.com", uploadedDocuments: ["selfie_1"], subjectSelections: {} },
      ] },
    });
    await page.signIn();
    await page.nav("Verify Teachers");
    page.button(".teacher-card", "✉ Send Message").click();
    (page.$("#msg-title") as HTMLInputElement).value = "Documents";
    (page.$("#msg-text") as HTMLTextAreaElement).value = "Please re-upload your ID.";
    page.button("#teacher-msg-modal", "Send Message").click();
    await page.settle();
    expect(page.callsTo("adminSendTeacherMessage")[0].data).toEqual({
      uid: "t-1", title: "Documents", text: "Please re-upload your ID.",
    });
  });
});

// ── Android pilot ─────────────────────────────────────────────────────────────

describe("android pilot", () => {
  it("approves a sign-up and reloads the list", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListPilotRegistrations: { registrations: [
        { id: "reg-1", email: "pilot@example.com", app: "teacher", lang: "he", status: "pending" },
      ] },
    });
    await page.signIn();
    await page.nav("Android Pilot");
    expect(page.$("#pilot-table").textContent).toContain("Pro Teacher");
    page.button("#pilot-table", "Approve & email").click();
    await page.settle();
    expect(page.callsTo("adminSetPilotStatus")[0].data).toEqual({ id: "reg-1", status: "approved" });
    expect(page.callsTo("adminListPilotRegistrations")).toHaveLength(2);
  });
});

// ── Bulk actions ──────────────────────────────────────────────────────────────

describe("multi-select", () => {
  const many = (n: number) =>
    Array.from({ length: n }, (_, i) => user({ uid: `u${i}`, email: `u${i}@example.com`, displayName: `User ${i}` }));

  async function usersPage(users: any[], extra: Record<string, any> = {}) {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: { users, nextPageToken: null },
      adminBulkDeleteUsers: (d: any) => ({ results: d.uids.map((uid: string) => ({ uid, status: "deleted" })) }),
      ...extra,
    });
    await page.signIn();
    await page.nav("Users");
    return page;
  }
  const tick = (p: NonNullable<typeof page>, uid: string) => {
    const box = p.$(`#students-table .row-select[data-id="${uid}"]`) as HTMLInputElement;
    box.checked = !box.checked;
    box.dispatchEvent(new p.window.Event("change", { bubbles: true }));
  };
  const selectAll = (p: NonNullable<typeof page>, on: boolean) => {
    const all = p.$("#students-select-all") as HTMLInputElement;
    all.checked = on;
    all.dispatchEvent(new p.window.Event("change", { bubbles: true }));
  };

  it("shows the action bar only while something is selected", async () => {
    const p = await usersPage(many(3));
    expect(p.$("#students-bulk-bar").classList.contains("show")).toBe(false);
    tick(p, "u0");
    tick(p, "u2");
    expect(p.$("#students-bulk-bar").classList.contains("show")).toBe(true);
    expect(p.$("#students-selected-count").textContent).toBe("2 selected");
    expect((p.$("#students-select-all") as HTMLInputElement).indeterminate).toBe(true);
    p.button("#students-bulk-bar", "Clear").click();
    expect(p.$("#students-bulk-bar").classList.contains("show")).toBe(false);
  });

  it("select-all takes only the rows the search shows, and keeps them across searches", async () => {
    const p = await usersPage([...many(3), user({ uid: "z", email: "zed@example.com", displayName: "Zed" })]);
    const search = p.$("#user-search") as HTMLInputElement;
    search.value = "zed";
    search.dispatchEvent(new p.window.Event("input"));
    await p.settle();
    selectAll(p, true);
    expect(p.$("#students-selected-count").textContent).toBe("1 selected");

    search.value = "";
    search.dispatchEvent(new p.window.Event("input"));
    await p.settle();
    expect((p.$(`#students-table .row-select[data-id="z"]`) as HTMLInputElement).checked).toBe(true);
    expect((p.$(`#students-table .row-select[data-id="u0"]`) as HTMLInputElement).checked).toBe(false);
  });

  it("deletes a large selection in chunks of 20 after one confirmation", async () => {
    const p = await usersPage(many(25));
    selectAll(p, true);
    p.button("#students-bulk-bar", "Delete selected").click();
    await p.settle(); await p.settle();
    expect(p.confirm).toHaveBeenCalledTimes(1);
    expect(p.confirm).toHaveBeenCalledWith(expect.stringContaining("Delete 25 users?"));
    expect(p.callsTo("adminBulkDeleteUsers").map((c) => c.data.uids.length)).toEqual([20, 5]);
    expect(p.$("#toast").textContent).toContain("Deleted 25");
  });

  it("deletes nothing when the confirmation is cancelled", async () => {
    const p = await usersPage(many(2));
    tick(p, "u1");
    p.confirm.mockReturnValueOnce(false);
    p.button("#students-bulk-bar", "Delete selected").click();
    await p.settle();
    expect(p.callsTo("adminBulkDeleteUsers")).toHaveLength(0);
  });

  it("reports skipped and failed accounts from a bulk delete", async () => {
    const p = await usersPage(many(3), {
      adminBulkDeleteUsers: { results: [
        { uid: "u0", status: "deleted" },
        { uid: "u1", status: "skipped", reason: "your own admin account" },
        { uid: "u2", status: "failed", reason: "End your active lesson first." },
      ] },
    });
    selectAll(p, true);
    p.button("#students-bulk-bar", "Delete selected").click();
    await p.settle(); await p.settle();
    const toast = p.$("#toast");
    expect(toast.textContent).toBe("Deleted 1 · skipped 1 · failed 1 (End your active lesson first.)");
    expect(toast.classList.contains("error")).toBe(true);
  });

  it("emails the selected users and says how many had no address", async () => {
    const p = await usersPage([...many(2), user({ uid: "guest", email: null, displayName: null })], {
      adminSendEmail: { sent: 2, failed: [], withoutEmail: 1, notFound: 0 },
    });
    selectAll(p, true);
    p.button("#students-bulk-bar", "📧 Email").click();
    expect(p.$("#email-modal").classList.contains("open")).toBe(true);
    expect(p.$("#email-to-label").textContent).toBe("3 selected users — 1 without an email will be skipped");

    p.button("#email-modal", "Send Email").click();
    await p.settle();
    expect(p.callsTo("adminSendEmail")).toHaveLength(0);

    (p.$("#email-subject") as HTMLInputElement).value = "New teachers";
    (p.$("#email-text") as HTMLTextAreaElement).value = "Come back and ask!";
    p.button("#email-modal", "Send Email").click();
    await p.settle();
    expect(p.callsTo("adminSendEmail")[0].data).toEqual({
      uids: ["u0", "u1", "guest"], subject: "New teachers", text: "Come back and ask!",
    });
    expect(p.$("#email-modal").classList.contains("open")).toBe(false);
    expect(p.$("#toast").textContent).toBe("Sent 2 · 1 without email");
  });
});

describe("anonymous cleanup", () => {
  async function cleanupModal(accounts: string[]) {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: { users: [], nextPageToken: null },
      adminFindInactiveAnonymous: (d: any) => ({
        days: d.days, scanned: 500, skippedWithBalance: 3,
        accounts: accounts.map((uid) => ({ uid, lastActiveAt: Date.UTC(2026, 8, 1) })),
      }),
      adminBulkDeleteUsers: (d: any) => ({ results: d.uids.map((uid: string) => ({ uid, status: "deleted" })) }),
    });
    await page.signIn();
    await page.nav("Users");
    page.button("#page-users", "🧹 Clean up anonymous").click();
    return page;
  }

  it("previews before deleting anything", async () => {
    const p = await cleanupModal(["g1", "g2"]);
    expect(p.$("#cleanup-modal").classList.contains("open")).toBe(true);
    expect(p.$("#cleanup-delete").style.display).toBe("none");

    p.button("#cleanup-modal", "Find").click();
    await p.settle();
    expect(p.callsTo("adminFindInactiveAnonymous")[0].data).toEqual({ days: 7 });
    const text = p.$("#cleanup-result").textContent!;
    expect(text).toContain("500");
    expect(text).toContain("inactive 7+ days");
    expect(text).toContain("still hold minutes");
    expect(p.$("#cleanup-delete").textContent).toBe("Delete 2 accounts");
    expect(p.callsTo("adminBulkDeleteUsers")).toHaveLength(0);
  });

  it("deletes in chunks and asks the server to re-check every account", async () => {
    const uids = Array.from({ length: 45 }, (_, i) => `g${i}`);
    const p = await cleanupModal(uids);
    (p.$("#cleanup-days") as HTMLInputElement).value = "14";
    p.button("#cleanup-modal", "Find").click();
    await p.settle();
    p.$("#cleanup-delete").click();
    for (let i = 0; i < 5; i++) await p.settle();

    const calls = p.callsTo("adminBulkDeleteUsers");
    expect(calls.map((c) => c.data.uids.length)).toEqual([20, 20, 5]);
    expect(calls.every((c) => c.data.requireInactiveAnonymousDays === 14)).toBe(true);
    expect(calls.flatMap((c) => c.data.uids)).toEqual(uids);
    expect((p.$("#cleanup-progress").firstElementChild as HTMLElement).style.width).toBe("100%");
    expect(p.$("#toast").textContent).toBe("Deleted 45");
    expect(p.$("#cleanup-delete").style.display).toBe("none");
  });

  it("hides the delete button when nothing qualifies", async () => {
    const p = await cleanupModal([]);
    p.button("#cleanup-modal", "Find").click();
    await p.settle();
    expect(p.$("#cleanup-delete").style.display).toBe("none");
  });
});

// ── Sorting and selection on every table ──────────────────────────────────────

describe("sorting", () => {
  const lessonsPage = async (lessons: any[]) => {
    page = openConsole({ adminDashboardStatus: dashboard(), adminListLessons: { lessons, hasMore: false } });
    await page.signIn();
    await page.nav("Lessons");
    return page;
  };
  const header = (p: NonNullable<typeof page>, scope: string, label: string) =>
    p.$$(`${scope} thead th`).find((th) => th.textContent!.trim() === label)!;
  const column = (p: NonNullable<typeof page>, tbody: string, label: string) => {
    const idx = (header(p, `#page-${tbody.replace("-table", "")}`, label) as HTMLTableCellElement).cellIndex;
    return p.$$(`#${tbody} tr`).map((r) => (r as HTMLTableRowElement).cells[idx].textContent!.trim());
  };
  const ids = (p: NonNullable<typeof page>, tbody: string) => p.$$(`#${tbody} tr`).map((r) => r.dataset.id);

  const lesson = (id: string, startedAt: number, costCents: number | null, durationSeconds: number | null) =>
    ({ id, status: "completed", startedAt, costCents, durationSeconds, currency: "ILS", studentUid: "s", teacherUid: "t" });

  it("sorts dates by time, not by their text, and reverses on a second click", async () => {
    // "Feb 3" sorts before "Jan 9" as text; by time January comes first.
    const p = await lessonsPage([
      lesson("feb", Date.UTC(2026, 1, 3), 100, 60),
      lesson("jan", Date.UTC(2026, 0, 9), 200, 60),
      lesson("mar", Date.UTC(2026, 2, 1), 300, 60),
    ]);
    header(p, "#page-lessons", "Started").click();
    expect(ids(p, "lessons-table")).toEqual(["jan", "feb", "mar"]);
    expect(header(p, "#page-lessons", "Started").classList.contains("sort-asc")).toBe(true);
    header(p, "#page-lessons", "Started").click();
    expect(ids(p, "lessons-table")).toEqual(["mar", "feb", "jan"]);
    expect(header(p, "#page-lessons", "Started").classList.contains("sort-desc")).toBe(true);
  });

  it("sorts money and durations by amount, and keeps blanks last either way", async () => {
    const p = await lessonsPage([
      lesson("nine", 1, 900, 59),
      lesson("blank", 2, null, null),
      lesson("twelve-hundred", 3, 120000, 3600),
      lesson("ten", 4, 1000, 125),
    ]);
    header(p, "#page-lessons", "Cost").click();
    expect(ids(p, "lessons-table")).toEqual(["nine", "ten", "twelve-hundred", "blank"]);
    header(p, "#page-lessons", "Cost").click();
    expect(ids(p, "lessons-table")).toEqual(["twelve-hundred", "ten", "nine", "blank"]);
    header(p, "#page-lessons", "Duration").click();
    expect(column(p, "lessons-table", "Duration")).toEqual(["59s", "2m 5s", "60m 0s", "—"]);
  });

  it("keeps the chosen order when the table reloads", async () => {
    const p = await lessonsPage([lesson("b", 2, 1, 1), lesson("a", 1, 1, 1)]);
    header(p, "#page-lessons", "Started").click();
    expect(ids(p, "lessons-table")).toEqual(["a", "b"]);
    await p.nav("Lessons");
    expect(ids(p, "lessons-table")).toEqual(["a", "b"]);
  });

  it("does not offer sorting on checkbox or action columns", async () => {
    page = openConsole({ adminDashboardStatus: dashboard(), adminListUsers: { users: [user()], nextPageToken: null } });
    await page.signIn();
    await page.nav("Users");
    const sortableLabels = (table: string) => {
      const ths = page!.$$(`#page-users table:has(#${table}) thead th`);
      return ths.filter((th) => th.classList.contains("sortable")).map((th) => th.textContent!.trim());
    };
    expect(sortableLabels("students-table")).toEqual(
      ["Email", "Display Name", "Role", "Remaining Min", "Total Min", "Joined", "Last Active", "Status"]
    );
    expect(sortableLabels("teachers-table")).toEqual(
      ["Email", "Display Name", "Minutes Taught", "Joined", "Last Active", "Status"]
    );
  });

  it("sorts text naturally, so user10 comes after user9", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: { users: ["user10", "user9", "User1"].map((n) => user({ uid: n, email: `${n}@x.com`, displayName: n })), nextPageToken: null },
    });
    await page.signIn();
    await page.nav("Users");
    header(page, "#page-users", "Display Name").click();
    expect(page.$$("#students-table tr").map((r) => r.dataset.id)).toEqual(["User1", "user9", "user10"]);
  });
});

describe("selection on other tables", () => {
  const tick = (p: NonNullable<typeof page>, tbody: string, id: string) => {
    const box = p.$(`#${tbody} .row-select[data-id="${id}"]`) as HTMLInputElement;
    box.checked = true;
    box.dispatchEvent(new p.window.Event("change", { bubbles: true }));
  };

  it("gives every main table a checkbox column, including its empty state", async () => {
    page = openConsole({ adminDashboardStatus: dashboard(), adminListQuestions: { questions: [], hasMore: false } });
    await page.signIn();
    await page.nav("Questions");
    expect(page.$("#page-questions thead th.select-cell input")).not.toBeNull();
    expect((page.$("#questions-table td") as HTMLTableCellElement).colSpan).toBe(14);
  });

  it("deletes only the unused coupons in a selection", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListCoupons: { coupons: [
        { id: "FREE1", numberOfMinutes: 10, createdAt: 1 },
        { id: "USED", numberOfMinutes: 10, createdAt: 2, activatedAt: 3 },
        { id: "FREE2", numberOfMinutes: 10, createdAt: 4 },
      ] },
    });
    await page.signIn();
    await page.nav("Coupons");
    for (const id of ["FREE1", "USED", "FREE2"]) tick(page, "coupons-table", id);
    expect(page.$("#coupons-selected-count").textContent).toBe("3 selected");
    page.button("#coupons-bulk-bar", "Delete selected").click();
    for (let i = 0; i < 4; i++) await page.settle();
    expect(page.confirm).toHaveBeenCalledWith(expect.stringContaining("1 activated one is kept"));
    expect(page.callsTo("adminDeleteCoupon").map((c) => c.data.couponId)).toEqual(["FREE1", "FREE2"]);
    expect(page.$("#toast").textContent).toBe("Deleted 2 · kept 1 activated");
  });

  it("approves selected pilot sign-ups", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListPilotRegistrations: { registrations: [
        { id: "r1", email: "a@x.com", app: "student", status: "pending" },
        { id: "r2", email: "b@x.com", app: "teacher", status: "pending" },
      ] },
    });
    await page.signIn();
    await page.nav("Android Pilot");
    tick(page, "pilot-table", "r1");
    tick(page, "pilot-table", "r2");
    page.button("#pilot-bulk-bar", "Approve selected").click();
    for (let i = 0; i < 4; i++) await page.settle();
    expect(page.callsTo("adminSetPilotStatus").map((c) => c.data)).toEqual([
      { id: "r1", status: "approved" }, { id: "r2", status: "approved" },
    ]);
  });

  it("takes several online teachers offline at once", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard({
        teachers: { total: 2, online: 2, staleProjections: 0, list: [
          { uid: "t1", displayName: "A", subjects: [], verified: true },
          { uid: "t2", displayName: "B", subjects: [], verified: true },
        ] },
      }),
    });
    await page.signIn();
    tick(page, "online-teachers-table", "t1");
    tick(page, "online-teachers-table", "t2");
    page.button("#online-teachers-bulk-bar", "Go offline").click();
    for (let i = 0; i < 4; i++) await page.settle();
    expect(page.callsTo("adminMutateUser").map((c) => c.data)).toEqual([
      { action: "goOffline", uid: "t1" }, { action: "goOffline", uid: "t2" },
    ]);
  });

  it("emails the senders of selected support requests", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListContactRequests: { requests: [
        { id: "c1", userId: "u1", userEmail: "a@x.com", title: "Help" },
        { id: "c2", userId: "u1", userEmail: "a@x.com", title: "Again" },
        { id: "c3", userId: "u2", userEmail: "b@x.com", title: "Bug" },
      ] },
      adminSendEmail: { sent: 2, failed: [], withoutEmail: 0, notFound: 0 },
    });
    await page.signIn();
    await page.nav("Support");
    for (const id of ["c1", "c2", "c3"]) tick(page, "support-table", id);
    page.button("#support-bulk-bar", "📧 Email senders").click();
    expect(page.$("#email-to-label").textContent).toBe("2 selected users");
    (page.$("#email-subject") as HTMLInputElement).value = "Re: your request";
    (page.$("#email-text") as HTMLTextAreaElement).value = "Fixed.";
    page.button("#email-modal", "Send Email").click();
    await page.settle();
    expect(page.callsTo("adminSendEmail")[0].data.uids).toEqual(["u1", "u2"]);
  });

  it("drops rows that disappear on reload from the selection", async () => {
    let coupons = [{ id: "A", createdAt: 1 }, { id: "B", createdAt: 2 }];
    page = openConsole({ adminDashboardStatus: dashboard(), adminListCoupons: () => ({ coupons }) });
    await page.signIn();
    await page.nav("Coupons");
    tick(page, "coupons-table", "A");
    tick(page, "coupons-table", "B");
    coupons = [{ id: "B", createdAt: 2 }];
    page.button("#page-coupons", "↻ Reload").click();
    await page.settle();
    expect(page.$("#coupons-selected-count").textContent).toBe("1 selected");
  });

  it("copies the full IDs of the selection", async () => {
    page = openConsole({ adminDashboardStatus: dashboard(), adminListPayments: { payments: [
      { id: "checkout-aaaaaaaaaaaa", status: "completed", createdAt: 1 },
      { id: "checkout-bbbbbbbbbbbb", status: "completed", createdAt: 2 },
    ] } });
    const writeText = jest.fn().mockResolvedValue(undefined);
    Object.defineProperty(page.window.navigator, "clipboard", { value: { writeText }, configurable: true });
    await page.signIn();
    await page.nav("Payments");
    tick(page, "payments-table", "checkout-aaaaaaaaaaaa");
    tick(page, "payments-table", "checkout-bbbbbbbbbbbb");
    page.button("#payments-bulk-bar", "Copy IDs").click();
    expect(writeText).toHaveBeenCalledWith("checkout-aaaaaaaaaaaa\ncheckout-bbbbbbbbbbbb");
  });

  it("exports the selected rows as CSV with full IDs and quoted fields", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListContactRequests: { requests: [
        { id: "req-1", userId: "u1", userEmail: "a@x.com", title: 'Says "hi", twice', description: "line" },
        { id: "req-2", userId: "u2", userEmail: "b@x.com", title: "Not exported" },
      ] },
    });
    let blob: Blob | undefined;
    page.window.URL.createObjectURL = (b: Blob) => { blob = b; return "blob:test"; };
    page.window.URL.revokeObjectURL = () => undefined;
    page.window.HTMLAnchorElement.prototype.click = function () { (page!.window as any).__downloaded = this.download; };
    await page.signIn();
    await page.nav("Support");
    tick(page, "support-table", "req-1");
    page.button("#support-bulk-bar", "Export CSV").click();

    const text = await new Promise<string>((done) => {
      const reader = new page!.window.FileReader();
      reader.onload = () => done(reader.result as string);
      reader.readAsText(blob!);
    });
    const csv = text.replace(/^\uFEFF/, "").split("\n");
    expect(csv[0]).toBe("id,Name,Email,Description,Device,Role,Sent At,Status");
    expect(csv).toHaveLength(2);
    expect(csv[1]).toMatch(/^req-1,—,a@x\.com,"Says ""hi"", twiceline",/);
    expect((page.window as any).__downloaded).toMatch(/^support-\d{4}-\d{2}-\d{2}\.csv$/);
  });
});

describe("demo users", () => {
  async function usersPage(users: any[]) {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: { users, nextPageToken: null },
      adminSetDemoUsers: (d: any) => ({ updated: d.uids.length }),
    });
    await page.signIn();
    await page.nav("Users");
    return page;
  }
  const tickIn = (p: NonNullable<typeof page>, table: string, uid: string) => {
    const box = p.$(`#${table} .row-select[data-id="${uid}"]`) as HTMLInputElement;
    box.checked = true;
    box.dispatchEvent(new p.window.Event("change", { bubbles: true }));
  };
  const setFilter = (p: NonNullable<typeof page>, value: string) => {
    const select = p.$("#user-demo-filter") as HTMLSelectElement;
    select.value = value;
    select.dispatchEvent(new p.window.Event("change"));
  };

  it("marks the selected users of both tables as demo after one confirmation", async () => {
    const p = await usersPage([
      user({ uid: "s1", displayName: "Dana" }),
      user({ uid: "s2", displayName: "Avi" }),
      user({ uid: "t1", displayName: "Yossi", role: "teacher" }),
    ]);
    const search = p.$("#user-search") as HTMLInputElement;
    search.value = "dana";
    search.dispatchEvent(new p.window.Event("input"));
    await p.settle();
    tickIn(p, "students-table", "s1");
    p.button("#students-bulk-bar", "🧪 Mark as demo").click();
    await p.settle();

    expect(p.confirm).toHaveBeenCalledTimes(1);
    expect(p.callsTo("adminSetDemoUsers")[0].data).toEqual({ uids: ["s1"], isDemo: true });
    expect(p.$('#students-table tr[data-id="s1"]').textContent).toContain("Demo");
    expect(p.$("#students-bulk-bar").classList.contains("show")).toBe(false);

    search.value = "";
    search.dispatchEvent(new p.window.Event("input"));
    await p.settle();
    tickIn(p, "teachers-table", "t1");
    p.button("#teachers-bulk-bar", "🧪 Mark as demo").click();
    await p.settle();
    expect(p.callsTo("adminSetDemoUsers")[1].data).toEqual({ uids: ["t1"], isDemo: true });
    expect(p.$('#teachers-table tr[data-id="t1"]').textContent).toContain("Demo");
  });

  it("unmarks demo users", async () => {
    const p = await usersPage([user({ uid: "s1", isDemoUser: true })]);
    tickIn(p, "students-table", "s1");
    p.button("#students-bulk-bar", "Unmark demo").click();
    await p.settle();
    expect(p.callsTo("adminSetDemoUsers")[0].data).toEqual({ uids: ["s1"], isDemo: false });
    expect(p.$('#students-table tr[data-id="s1"]').textContent).not.toContain("Demo");
  });

  it("changes nothing when the confirmation is declined", async () => {
    const p = await usersPage([user({ uid: "s1" })]);
    p.confirm.mockReturnValueOnce(false);
    tickIn(p, "students-table", "s1");
    p.button("#students-bulk-bar", "🧪 Mark as demo").click();
    await p.settle();
    expect(p.callsTo("adminSetDemoUsers")).toHaveLength(0);
  });

  it("filters to demo users only, or hides them", async () => {
    const p = await usersPage([
      user({ uid: "s1", isDemoUser: true }),
      user({ uid: "s2" }),
      user({ uid: "t1", role: "teacher", isDemoUser: true }),
    ]);
    setFilter(p, "demo");
    expect(p.$$("#students-table tr").map((r) => r.dataset.id)).toEqual(["s1"]);
    expect(p.$$("#teachers-table tr").map((r) => r.dataset.id)).toEqual(["t1"]);
    setFilter(p, "real");
    expect(p.$$("#students-table tr").map((r) => r.dataset.id)).toEqual(["s2"]);
    expect(p.$("#teachers-table").textContent).toContain("No teachers found");
  });

  it("says on the overview how many demo users are left out", async () => {
    page = openConsole({ adminDashboardStatus: dashboard({ demoUsers: 3 }) });
    await page.signIn();
    expect(page.$("#overview-updated").textContent).toContain("3 demo users excluded from all figures");
  });
});

describe("support tickets", () => {
  const ticket = (overrides: any = {}) => ({
    id: "case-1", userId: "u1", userName: "Dana", userEmail: "dana@example.com",
    title: "Can't join", description: "The lesson won't start.\nPlease help.",
    deviceType: "iPhone 16", osVersion: "iOS 26.3", locale: "he_IL", role: "student",
    sentAt: "2026-10-19T08:00:00Z", sentAtMs: Date.UTC(2026, 9, 19, 8), ...overrides,
  });

  async function openSupport(requests: any[], respond?: (data: any) => any) {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListContactRequests: { requests },
      ...(respond ? { adminRespondToContactRequest: respond } : {}),
    });
    await page.signIn();
    await page.nav("Support");
    return page;
  }

  it("lists name, email, description, device, role and date", async () => {
    const p = await openSupport([ticket()]);
    const headers = p.$$("#page-support thead th").map((th) => th.textContent).filter(Boolean);
    expect(headers).toEqual(["Name", "Email", "Description", "Device", "Role", "Sent At", "Status"]);
    const row = p.$("#support-table tr").textContent!;
    for (const text of ["Dana", "dana@example.com", "The lesson won't start.", "iPhone 16", "student", "Open"]) {
      expect(row).toContain(text);
    }
  });

  it("opens the full ticket when a row is clicked, but not from its checkbox", async () => {
    const p = await openSupport([ticket()]);
    (p.$("#support-table tr .select-cell input") as HTMLInputElement).click();
    expect(p.$("#support-modal").classList.contains("open")).toBe(false);

    (p.$("#support-table tr td:nth-child(3)") as HTMLElement).click();
    expect(p.$("#support-modal").classList.contains("open")).toBe(true);
    const body = p.$("#support-modal-body").textContent!;
    for (const text of ["case-1", "Dana", "dana@example.com", "u1", "iOS 26.3", "he_IL", "Please help."]) {
      expect(body).toContain(text);
    }
    expect(p.$("#support-reply-to").textContent).toBe("→ dana@example.com");
  });

  it("sends a response and shows it on the ticket", async () => {
    const sentAt = Date.UTC(2026, 9, 20, 9);
    const p = await openSupport([ticket()], ({ requestId, message }) => ({
      response: { to: "dana@example.com", subject: `Re: Can't join [Case #${requestId}]`, message, sentAt, sentBy: "admin@example.com" },
    }));
    (p.$("#support-table tr td:nth-child(2)") as HTMLElement).click();
    (p.$("#support-reply-text") as HTMLTextAreaElement).value = "  Try updating the app.  ";
    p.button("#support-modal", "Send response").click();
    await p.settle();

    expect(p.confirm).toHaveBeenCalledWith("Send this response to dana@example.com?");
    expect(p.callsTo("adminRespondToContactRequest")[0].data).toEqual({ requestId: "case-1", message: "Try updating the app." });
    expect(p.$("#support-modal-body").textContent).toContain("Try updating the app.");
    expect(p.$("#support-modal-body").textContent).toContain("[Case #case-1]");
    expect(p.$("#support-reply-text") as HTMLTextAreaElement).toHaveProperty("value", "");
    expect(p.$("#support-table tr").textContent).toContain("Replied");
  });

  it("does not send an empty response", async () => {
    const p = await openSupport([ticket()], () => ({ response: {} }));
    (p.$("#support-table tr td:nth-child(2)") as HTMLElement).click();
    p.button("#support-modal", "Send response").click();
    await p.settle();
    expect(p.callsTo("adminRespondToContactRequest")).toHaveLength(0);
  });

  it("cannot reply to a ticket with no email", async () => {
    const p = await openSupport([ticket({ userEmail: "" })]);
    (p.$("#support-table tr td:nth-child(2)") as HTMLElement).click();
    expect((p.button("#support-modal", "Send response") as HTMLButtonElement).disabled).toBe(true);
  });

  it("escapes what the sender wrote", async () => {
    const p = await openSupport([ticket({ userName: EVIL, description: EVIL, title: EVIL })]);
    (p.$("#support-table tr td:nth-child(2)") as HTMLElement).click();
    await p.settle();
    expect((p.window as any).__pwned).toBeUndefined();
    expect(p.$("#support-modal-body img")).toBeNull();
  });
});

describe("last activity", () => {
  const DAY = 24 * 3600 * 1000;

  it("shows when the app was last open, not the last explicit sign-in", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: { users: [user({ lastSignIn: Date.now() - 40 * DAY, lastActiveAt: Date.now() - 2 * 3600 * 1000 })], nextPageToken: null },
    });
    await page.signIn();
    await page.nav("Users");
    const idx = (page.$$("#page-users thead th").find((th) => th.textContent === "Last Active") as HTMLTableCellElement).cellIndex;
    const cell = (page.$("#students-table tr") as HTMLTableRowElement).cells[idx];
    expect(cell.textContent).toBe("2h ago");
    expect(cell.getAttribute("title")).toMatch(/^Active: .+\nSigned in: .+/);
  });

  it("falls back to the sign-in time when no activity is known", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: { users: [user({ lastSignIn: Date.now() - 3 * DAY, lastActiveAt: null })], nextPageToken: null },
    });
    await page.signIn();
    await page.nav("Users");
    expect(page.$("#students-table").textContent).toContain("3d ago");
  });

  it("lists both times in the user detail window", async () => {
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: { users: [user()], nextPageToken: null },
      adminGetUserDetail: {
        auth: { uid: "uid-1", email: "dana@example.com", providers: ["password"], lastSignIn: Date.now() - 40 * DAY, lastActiveAt: Date.now() - 5 * 60 * 1000 },
        firestore: { role: "student" }, teacherDoc: null, purchases: [], questions: [], taughtQuestions: [],
        ratings: [], messages: [], presence: null, onlineEntry: null,
      },
    });
    await page.signIn();
    await page.nav("Users");
    page.button("#students-table", "View").click();
    await page.settle();
    const rows = page.$$("#user-modal-body .info-row").map((r) => r.textContent!.replace(/\s+/g, " ").trim());
    expect(rows).toContain("Last Active5m ago");
    expect(rows).toContain("Last Sign-In40d ago");
  });
});

describe("loading every user", () => {
  const DAY = 24 * 3600 * 1000;
  /** Three pages, with the account searched for on the last one and a
   *  look-alike on the first — the case that showed the wrong last activity. */
  function pagedUsers() {
    const pages = [
      [user({ uid: "lookalike", email: "s1@a.net", displayName: "Din", lastActiveAt: Date.now() - 101 * DAY })],
      [user({ uid: "other", email: "x@a.com", displayName: "X" })],
      [user({ uid: "s1", email: "s1@a.com", displayName: "student1", lastActiveAt: Date.now() - 16 * 60 * 1000 })],
    ];
    return (d: any) => {
      const i = d.pageToken ? Number(d.pageToken) : 0;
      return { users: pages[i], nextPageToken: i + 1 < pages.length ? String(i + 1) : null };
    };
  }

  it("fetches every page in large chunks before showing the list", async () => {
    page = openConsole({ adminDashboardStatus: dashboard(), adminListUsers: pagedUsers() });
    await page.signIn();
    await page.nav("Users");
    for (let i = 0; i < 3; i++) await page.settle();
    expect(page.callsTo("adminListUsers").map((c) => c.data)).toEqual([
      { limit: 1000 }, { pageToken: "1", limit: 1000 }, { pageToken: "2", limit: 1000 },
    ]);
    expect(page.$$("#students-table tr")).toHaveLength(3);
    expect(page.$("#users-updated").textContent).toMatch(/^3 users · last updated /);
    expect(page.$("#page-users").textContent).not.toContain("Load more");
  });

  it("finds an account on a later page instead of a look-alike from page 1", async () => {
    page = openConsole({ adminDashboardStatus: dashboard(), adminListUsers: pagedUsers() });
    await page.signIn();
    await page.nav("Users");
    for (let i = 0; i < 3; i++) await page.settle();
    const search = page.$("#user-search") as HTMLInputElement;
    search.value = "s1@a.com";
    search.dispatchEvent(new page.window.Event("input"));
    await page.settle();
    const rows = page.$$("#students-table tr");
    expect(rows.map((r) => r.dataset.id)).toEqual(["s1"]);
    expect(rows[0].textContent).toContain("16m ago");
  });

  it("force refresh reloads everything and keeps the search", async () => {
    let active = Date.now() - 101 * DAY;
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: () => ({ users: [user({ uid: "s1", email: "s1@a.com", lastActiveAt: active })], nextPageToken: null }),
    });
    await page.signIn();
    await page.nav("Users");
    const search = page.$("#user-search") as HTMLInputElement;
    search.value = "s1@a.com";
    search.dispatchEvent(new page.window.Event("input"));
    expect(page.$("#students-table").textContent).toContain("101d ago");

    active = Date.now() - 60 * 1000;
    page.button("#page-users", "⟳ Force refresh").click();
    expect(page.$("#users-force-refresh").textContent).toBe("⟳ Refreshing…");
    for (let i = 0; i < 3; i++) await page.settle();
    expect(page.$("#students-table").textContent).toContain("1m ago");
    expect(search.value).toBe("s1@a.com");
    expect(page.$("#toast").textContent).toBe("Reloaded all 1 users");
    expect((page.$("#users-force-refresh") as HTMLButtonElement).disabled).toBe(false);
  });

  it("ignores a slower, older load that finishes after a newer one", async () => {
    let release: (v: any) => void = () => undefined;
    let n = 0;
    page = openConsole({
      adminDashboardStatus: dashboard(),
      adminListUsers: () => (++n === 1
        ? new Promise((r) => { release = r; })
        : { users: [user({ uid: "new", email: "new@a.com" })], nextPageToken: null }),
    });
    await page.signIn();
    await page.nav("Users");          // first load hangs
    page.button("#page-users", "⟳ Force refresh").click();
    for (let i = 0; i < 3; i++) await page.settle();
    release({ users: [user({ uid: "old", email: "old@a.com" })], nextPageToken: null });
    for (let i = 0; i < 3; i++) await page.settle();
    expect(page.$$("#students-table tr").map((r) => r.dataset.id)).toEqual(["new"]);
  });
});
