import { createHmac } from "crypto";

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

import { authHeaders, parseTranzilaNotification } from "../tranzila";

describe("authHeaders", () => {
  // The docs' PHP: hash_hmac('sha256', $appKey, $secret . $time . $nonce) —
  // the app key is the message, secret + time + nonce the key.
  test("signs the app key with secret + request time + nonce", () => {
    const headers = authHeaders("app-key", "secret", 1700000000, "nonce");

    expect(headers).toEqual({
      "X-tranzila-api-app-key": "app-key",
      "X-tranzila-api-request-time": "1700000000",
      "X-tranzila-api-nonce": "nonce",
      "X-tranzila-api-access-token": createHmac("sha256", "secret1700000000nonce")
        .update("app-key")
        .digest("hex"),
    });
  });

  test("uses a fresh 40-byte nonce per request", () => {
    const a = authHeaders("app-key", "secret")["X-tranzila-api-nonce"];
    const b = authHeaders("app-key", "secret")["X-tranzila-api-nonce"];

    expect(a).toMatch(/^[0-9a-f]{80}$/);
    expect(a).not.toBe(b);
  });
});

describe("parseTranzilaNotification", () => {
  test("reads the classic form fields and the checkout from pdesc", () => {
    const note = parseTranzilaNotification({
      Response: "000",
      sum: "12.50",
      index: "987",
      tranmode: "A",
      pdesc: "checkout 1b4e28ba-2fa1-11d2-883f-0016d3cca427",
    });

    expect(note).toEqual({
      success: true,
      amount: 12.5,
      transactionId: "987",
      thtk: undefined,
      checkoutId: "1b4e28ba-2fa1-11d2-883f-0016d3cca427",
      tranMode: "A",
    });
  });

  test("reads the Hosted Fields shape", () => {
    const note = parseTranzilaNotification({
      transaction_response: { success: true, transaction_id: 42, amount: 10 },
      request_params: { checkout_id: "c-1" },
    });

    expect(note).toMatchObject({ success: true, transactionId: "42", amount: 10, checkoutId: "c-1" });
  });

  test("a declined response is not a success", () => {
    expect(parseTranzilaNotification({ Response: "033", sum: "10" }).success).toBe(false);
  });
});
