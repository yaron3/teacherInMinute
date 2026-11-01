const mockCreateBraintreeSale = jest.fn();
const mockVerifyWebhookSignature = jest.fn();
const mockCreateCardTransaction = jest.fn();

// ─── A Firestore small enough to reason about ────────────────────────────────
// Documents live in one map keyed by path. `runTransaction` runs its body once
// against the same store, which is all these tests need: they check what a
// cancel path is *allowed* to write, not Firestore's contention behaviour.

type DocData = Record<string, unknown>;
const store = new Map<string, DocData>();

function docSnapshot(path: string) {
  const data = store.get(path);
  return {
    exists: data !== undefined,
    id: path.split("/").pop() as string,
    data: () => data,
  };
}

function docRef(path: string) {
  return {
    id: path.split("/").pop() as string,
    path,
    get: async () => docSnapshot(path),
    set: async (data: DocData, options?: { merge?: boolean }) => {
      store.set(path, options?.merge ? { ...(store.get(path) ?? {}), ...data } : { ...data });
    },
    update: async (data: DocData) => {
      store.set(path, { ...(store.get(path) ?? {}), ...data });
    },
    collection: (name: string) => collectionRef(`${path}/${name}`),
  };
}

type FakeDocRef = ReturnType<typeof docRef>;

function collectionRef(path: string) {
  // `where`/`limit` exist for the lesson lookup a credited purchase makes; no
  // test here runs a lesson, so an empty result is the right answer.
  const emptyQuery = {
    where: () => emptyQuery,
    limit: () => emptyQuery,
    get: async () => ({ empty: true, size: 0, docs: [] }),
  };
  return {
    doc: (id: string) => docRef(`${path}/${id}`),
    where: () => emptyQuery,
    limit: () => emptyQuery,
  };
}

const fakeFirestore = {
  collection: (name: string) => collectionRef(name),
  runTransaction: async <T>(
    body: (tx: {
      get: (ref: FakeDocRef) => Promise<ReturnType<typeof docSnapshot>>;
      update: (ref: FakeDocRef, data: DocData) => void;
      set: (ref: FakeDocRef, data: DocData, options?: { merge?: boolean }) => void;
    }) => Promise<T>
  ): Promise<T> =>
    body({
      get: (ref) => ref.get(),
      update: (ref, data) => {
        void ref.update(data);
      },
      set: (ref, data, options) => {
        void ref.set(data, options);
      },
    }),
};

jest.mock("firebase-admin", () => ({
  firestore: () => fakeFirestore,
  // payments.ts reaches the lesson a purchase may be extending, and that module
  // graph takes a realtime handle at import. Nothing here exercises it.
  database: () => ({
    ref: () => ({
      once: async () => ({ exists: () => false, val: () => null }),
      update: async () => undefined,
      remove: async () => undefined,
      set: async () => undefined,
    }),
  }),
}));

jest.mock("firebase-admin/firestore", () => ({
  FieldValue: {
    increment: (n: number) => ({ __increment: n }),
    delete: () => ({ __delete: true }),
  },
  Timestamp: {
    now: () => ({ __timestamp: "now" }),
    fromMillis: (millis: number) => ({ __timestamp: millis }),
  },
}));

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

jest.mock("firebase-functions/v2/https", () => ({
  onCall: (handler: unknown) => handler,
  onRequest: (handler: unknown) => handler,
  HttpsError: class HttpsError extends Error {
    constructor(public code: string, message: string, public details?: unknown) {
      super(message);
    }
  },
}));

jest.mock("uuid", () => ({ v4: () => "generated-id" }));

jest.mock("../paypal", () => ({
  ...jest.requireActual("../paypal"),
  createOrder: jest.fn(),
  captureOrder: jest.fn(),
  verifyWebhookSignature: (...args: unknown[]) => mockVerifyWebhookSignature(...args),
}));

jest.mock("../braintree", () => ({
  ...jest.requireActual("../braintree"),
  createBraintreeSale: (...args: unknown[]) => mockCreateBraintreeSale(...args),
  generateBraintreeClientToken: jest.fn(),
}));

jest.mock("../tranzila", () => ({
  ...jest.requireActual("../tranzila"),
  createCardTransaction: (...args: unknown[]) => mockCreateCardTransaction(...args),
  createHandshake: jest.fn(),
}));

import {
  confirmGooglePayPayment,
  createApplePayCheckout,
  createGooglePayCheckout,
  paypalCancel,
  paypalWebhook,
  tranzilaCharge,
  tranzilaNotify,
} from "../payments";
import { generateBraintreeClientToken } from "../braintree";
import { TranzilaApiError } from "../tranzila";

type RequestHandler = (
  req: { method?: string; query: Record<string, string | undefined>; headers?: Record<string, string>; body?: unknown },
  res: FakeResponse
) => Promise<void>;

type CallableHandler = (request: {
  auth?: { uid: string };
  data: Record<string, unknown>;
}) => Promise<unknown>;

interface FakeResponse {
  redirect: jest.Mock;
  status: jest.Mock;
  send: jest.Mock;
  json: jest.Mock;
  setHeader: jest.Mock;
}

function fakeResponse(): FakeResponse {
  const res: Partial<FakeResponse> = {
    redirect: jest.fn(),
    send: jest.fn(),
    json: jest.fn(),
    setHeader: jest.fn(),
  };
  res.status = jest.fn(() => res as FakeResponse);
  return res as FakeResponse;
}

const CHECKOUT_PATH = "paymentCheckouts/checkout-1";

function seedCheckout(overrides: DocData = {}): void {
  store.set(CHECKOUT_PATH, {
    uid: "student-1",
    packageId: "pkg-1",
    priceCents: 1000,
    currency: "ILS",
    minutes: 30,
    status: "paypal_created",
    paypalOrderId: "order-1",
    ...overrides,
  });
}

function checkoutStatus(): unknown {
  return store.get(CHECKOUT_PATH)?.status;
}

beforeEach(() => {
  jest.clearAllMocks();
  store.clear();
});

describe("paypalCancel", () => {
  const cancel = paypalCancel as unknown as RequestHandler;

  test("cancels a checkout the buyer backed out of", async () => {
    seedCheckout();

    await cancel({ query: { checkoutId: "checkout-1", token: "order-1" } }, fakeResponse());

    expect(checkoutStatus()).toBe("cancelled");
  });

  // The endpoint needs no authentication — PayPal sends the buyer here — and a
  // browser Back after paying lands on it just the same.
  test("leaves a checkout that already completed", async () => {
    seedCheckout({ status: "completed", paypalCaptureId: "capture-1" });

    await cancel({ query: { checkoutId: "checkout-1", token: "order-1" } }, fakeResponse());

    expect(checkoutStatus()).toBe("completed");
  });

  test("ignores a cancel carrying someone else's order id", async () => {
    seedCheckout();

    await cancel({ query: { checkoutId: "checkout-1", token: "order-999" } }, fakeResponse());

    expect(checkoutStatus()).toBe("paypal_created");
  });

  test("still sends the buyer back to the app", async () => {
    seedCheckout();
    const res = fakeResponse();

    await cancel({ query: { checkoutId: "checkout-1" } }, res);

    expect(res.redirect).toHaveBeenCalledWith(
      302,
      expect.stringContaining("teacherminute://payment-return?status=cancelled")
    );
  });
});

describe("a declined wallet payment", () => {
  const confirm = confirmGooglePayPayment as unknown as CallableHandler;

  test("does not cancel a checkout that another path completed first", async () => {
    seedCheckout({ status: "created" });

    // The real race: this sale fails while a webhook (or the redirect return)
    // captures and completes the same checkout.
    mockCreateBraintreeSale.mockImplementation(async () => {
      store.set(CHECKOUT_PATH, { ...(store.get(CHECKOUT_PATH) as DocData), status: "completed" });
      return { success: false, message: "declined" };
    });

    await expect(
      confirm({ auth: { uid: "student-1" }, data: { checkoutId: "checkout-1", nonce: "nonce-1" } })
    ).rejects.toThrow("declined");

    expect(checkoutStatus()).toBe("completed");
  });

  test("cancels the checkout when nothing else completed it", async () => {
    seedCheckout({ status: "created" });
    mockCreateBraintreeSale.mockResolvedValue({ success: false, message: "declined" });

    await expect(
      confirm({ auth: { uid: "student-1" }, data: { checkoutId: "checkout-1", nonce: "nonce-1" } })
    ).rejects.toThrow("declined");

    expect(checkoutStatus()).toBe("cancelled");
  });
});

describe("paypalWebhook PAYMENT.CAPTURE.DENIED", () => {
  const webhook = paypalWebhook as unknown as RequestHandler;
  const originalEnv = { ...process.env };

  beforeEach(() => {
    process.env = { ...originalEnv, PAYPAL_WEBHOOK_ID: "webhook-1" };
    mockVerifyWebhookSignature.mockResolvedValue(true);
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  function deniedEvent() {
    return {
      method: "POST",
      query: {},
      headers: {},
      body: {
        id: "event-1",
        event_type: "PAYMENT.CAPTURE.DENIED",
        resource: { id: "capture-1", invoice_id: "checkout-1" },
      },
    };
  }

  test("leaves a checkout that already completed", async () => {
    seedCheckout({ status: "completed" });

    await webhook(deniedEvent(), fakeResponse());

    expect(checkoutStatus()).toBe("completed");
  });

  test("cancels one that had not", async () => {
    seedCheckout();

    await webhook(deniedEvent(), fakeResponse());

    expect(checkoutStatus()).toBe("cancelled");
  });
});

describe("tranzilaCharge", () => {
  const charge = tranzilaCharge as unknown as RequestHandler;
  const body = { checkoutId: "checkout-1", token: "tok-1", expiryMonth: "07", expiryYear: "27" };

  function seedTranzilaCheckout(overrides: DocData = {}): void {
    seedCheckout({ status: "tranzila_created", paypalOrderId: null, ...overrides });
  }

  test("debits the stored price and credits the minutes", async () => {
    seedTranzilaCheckout();
    mockCreateCardTransaction.mockResolvedValue({ transactionId: "txn-1", authNumber: "0587923" });
    const res = fakeResponse();

    await charge({ method: "POST", query: {}, body }, res);

    expect(mockCreateCardTransaction).toHaveBeenCalledWith(
      expect.objectContaining({ token: "tok-1", expireMonth: 7, expireYear: 2027, amountCents: 1000, currency: "ILS" })
    );
    expect(store.get(CHECKOUT_PATH)).toMatchObject({
      status: "completed",
      tranzilaTransactionId: "txn-1",
      tranzilaAuthNumber: "0587923",
    });
    expect(store.get("users/student-1")).toMatchObject({ remainingMinutes: { __increment: 30 } });
    expect(store.get("users/student-1/purchases/checkout-1")).toMatchObject({ provider: "tranzila" });
    expect(res.json).toHaveBeenCalledWith({
      redirectUrl: expect.stringContaining("teacherminute://payment-return?status=success"),
    });
  });

  // A double-tap or replayed request arrives while the first debit is running.
  test("never charges a checkout that is already charging", async () => {
    seedTranzilaCheckout({ status: "tranzila_charging" });
    const res = fakeResponse();

    await charge({ method: "POST", query: {}, body }, res);

    expect(mockCreateCardTransaction).not.toHaveBeenCalled();
    expect(res.status).toHaveBeenCalledWith(409);
  });

  test("lets the buyer retry after a decline", async () => {
    seedTranzilaCheckout();
    mockCreateCardTransaction.mockRejectedValue(new TranzilaApiError(0, "declined"));
    const res = fakeResponse();

    await charge({ method: "POST", query: {}, body }, res);

    expect(checkoutStatus()).toBe("tranzila_created");
    expect(res.json).toHaveBeenCalledWith(expect.objectContaining({ retry: true }));
  });

  test("holds the checkout when the outcome is unknown", async () => {
    seedTranzilaCheckout();
    mockCreateCardTransaction.mockRejectedValue(new Error("socket hang up"));
    const res = fakeResponse();

    await charge({ method: "POST", query: {}, body }, res);

    expect(checkoutStatus()).toBe("tranzila_charging");
    expect(res.status).toHaveBeenCalledWith(502);

    // ...and the buyer backing out does not close it either.
    await (paypalCancel as unknown as RequestHandler)({ query: { checkoutId: "checkout-1" } }, fakeResponse());
    expect(checkoutStatus()).toBe("tranzila_charging");
  });
});

describe("tranzilaNotify", () => {
  const notify = tranzilaNotify as unknown as RequestHandler;
  const originalEnv = { ...process.env };
  const paid = { Response: "000", sum: "10.00", index: "555", pdesc: "checkout checkout-1" };

  beforeEach(() => {
    process.env = { ...originalEnv, TRANZILA_NOTIFY_KEY: "notify-key" };
  });

  afterAll(() => {
    process.env = originalEnv;
  });

  // The checkout id in `pdesc` comes from the browser; only the key proves
  // the call is Tranzila's.
  test("refuses a notification without the key", async () => {
    seedCheckout({ status: "tranzila_created", paymentMethod: "apple_pay" });
    const res = fakeResponse();

    await notify({ method: "POST", query: { key: "guess" }, body: paid }, res);

    expect(res.status).toHaveBeenCalledWith(403);
    expect(checkoutStatus()).toBe("tranzila_created");
  });

  test("credits a paid wallet checkout", async () => {
    seedCheckout({ status: "tranzila_created", paymentMethod: "apple_pay" });
    // pdesc carries a uuid in production; the fake checkout id is not one.
    await notify(
      { method: "POST", query: { key: "notify-key" }, body: { ...paid, checkout_id: "checkout-1" } },
      fakeResponse()
    );

    expect(store.get(CHECKOUT_PATH)).toMatchObject({ status: "completed", tranzilaTransactionId: "555" });
    expect(store.get("users/student-1")).toMatchObject({ remainingMinutes: { __increment: 30 } });
  });

  test("ignores a paid amount that differs from the price", async () => {
    seedCheckout({ status: "tranzila_created", paymentMethod: "google_pay" });

    await notify(
      { method: "POST", query: { key: "notify-key" }, body: { ...paid, sum: "1.00", checkout_id: "checkout-1" } },
      fakeResponse()
    );

    expect(checkoutStatus()).toBe("tranzila_created");
  });

  // A card's J2 check notifies too, while the buyer has not paid yet.
  test("does not credit a card checkout that was only validated", async () => {
    seedCheckout({ status: "tranzila_created", paymentMethod: "credit_card" });

    await notify(
      { method: "POST", query: { key: "notify-key" }, body: { ...paid, checkout_id: "checkout-1" } },
      fakeResponse()
    );

    expect(checkoutStatus()).toBe("tranzila_created");
  });
});

describe("wallet checkout routing", () => {
  const applePay = createApplePayCheckout as unknown as CallableHandler;
  const googlePay = createGooglePayCheckout as unknown as CallableHandler;
  const originalEnv = process.env;

  const TRANZILA_ENV = {
    TRANZILA_APP_KEY: "app-key",
    TRANZILA_SECRET: "secret",
    TRANZILA_TERMINAL_NAME: "terminal",
    TRANZILA_NOTIFY_KEY: "notify-key",
    TRANZILA_WALLETS: "apple_pay,google_pay",
  };

  function withEnv(env: Record<string, string | undefined>): void {
    process.env = { ...originalEnv };
    for (const key of Object.keys(TRANZILA_ENV)) delete process.env[key];
    for (const [key, value] of Object.entries(env)) {
      if (value !== undefined) process.env[key] = value;
    }
  }

  beforeEach(() => {
    store.set("pricing/pkg-1", { minutes: 30, priceCents: 1000, currency: "ILS", type: "minutes" });
    (generateBraintreeClientToken as jest.Mock).mockResolvedValue("braintree-token");
  });

  afterEach(() => {
    process.env = originalEnv;
  });

  const request = { auth: { uid: "student-1" }, data: { packageId: "pkg-1" } };

  test.each([
    ["Tranzila is not set at all", {}],
    ["TRANZILA_WALLETS is empty", { ...TRANZILA_ENV, TRANZILA_WALLETS: "" }],
    ["the Tranzila keys are missing", { TRANZILA_WALLETS: "apple_pay,google_pay" }],
    ["the notify key is missing", { ...TRANZILA_ENV, TRANZILA_NOTIFY_KEY: undefined }],
  ])("stays on native Braintree when %s", async (_label, env) => {
    withEnv(env);

    for (const checkout of [applePay, googlePay]) {
      const result = (await checkout(request)) as Record<string, unknown>;
      expect(result.clientToken).toBe("braintree-token");
      expect(result).not.toHaveProperty("checkoutUrl");
    }
    expect(generateBraintreeClientToken).toHaveBeenCalledTimes(2);
  });

  test("moves only the wallets TRANZILA_WALLETS lists", async () => {
    withEnv({ ...TRANZILA_ENV, TRANZILA_WALLETS: "apple_pay" });

    const apple = (await applePay(request)) as Record<string, unknown>;
    const google = (await googlePay(request)) as Record<string, unknown>;

    expect(apple.checkoutUrl).toEqual(expect.stringContaining("tranzilaCheckout?checkoutId="));
    expect(google.clientToken).toBe("braintree-token");
  });
});
