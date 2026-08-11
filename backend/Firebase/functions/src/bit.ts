import { logger } from "firebase-functions";

// ─── Bit checkout (stub) ───────────────────────────────────────────────────
//
// Bit is an Israeli app-to-app payment method. It is unrelated to PayPal and
// is not one of PayPal's supported payment_source wallets, so it needs its
// own acquirer/PSP integration (e.g. Tranzila, Cardcom, PayPlus, Grow/Meshulam,
// or a direct "Bit for Business" API) before this can go live.
//
// To turn this on:
//   1. Get a Bit-capable merchant account and API credentials from a supported
//      Israeli PSP.
//   2. Add the credentials to functions/.env (mirroring PAYPAL_CLIENT_ID/SECRET).
//   3. Replace the body of `createBitOrder` below with a real call to that
//      provider's order/payment-link API, returning a checkout URL the buyer
//      opens to complete payment with the Bit app.
//   4. Add a webhook endpoint (mirroring `paypalWebhook`) so the provider can
//      notify us of completion, and a `bitSuccess` HTTP redirect endpoint
//      (mirroring `paypalSuccess`) for the buyer's return trip — both should
//      credit minutes through the same `paymentCheckouts` + transaction
//      pattern used for PayPal.

export interface CreateBitOrderParams {
  amountCents: number;
  currency: string;
  description: string;
  uid: string;
  sessionId: string;
  returnUrl: string;
  cancelUrl: string;
}

export class BitNotConfiguredError extends Error {
  constructor() {
    super("Bit payments are not configured yet");
    this.name = "BitNotConfiguredError";
  }
}

export async function createBitOrder(params: CreateBitOrderParams): Promise<never> {
  logger.warn(
    `[bit] createBitOrder called but no provider is configured sessionId=${params.sessionId} uid=${params.uid}`
  );
  throw new BitNotConfiguredError();
}
