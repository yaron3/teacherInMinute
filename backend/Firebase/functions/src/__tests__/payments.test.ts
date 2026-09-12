const mockCreateBraintreeSale = jest.fn();
const mockVerifyWebhookSignature = jest.fn();

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
  return { doc: (id: string) => docRef(`${path}/${id}`) };
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

import { confirmGooglePayPayment, paypalCancel, paypalWebhook } from "../payments";

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
  setHeader: jest.Mock;
}

function fakeResponse(): FakeResponse {
  const res: Partial<FakeResponse> = {
    redirect: jest.fn(),
    send: jest.fn(),
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
