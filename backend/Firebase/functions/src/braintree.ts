import { logger } from "firebase-functions";
import * as braintree from "braintree";

// ─── Braintree — native Apple Pay processing ──────────────────────────────
//
// Apple Pay needs a real native PassKit sheet in the app, which PayPal's
// plain Checkout/Orders v2 API (used everywhere else in this file's sibling
// paypal.ts) does not support — that API's Apple Pay support is JS-SDK/web
// only. Braintree (a separate PayPal-owned payment platform) is what
// actually accepts a native PKPayment token from the app.
//
// To turn this on:
//   1. Create/access a Braintree account (via the PayPal Business account or
//      braintreegateway.com) and get merchant ID / public key / private key.
//   2. Register an Apple Merchant ID in the Apple Developer portal
//      (Certificates, Identifiers & Profiles → Merchant IDs), e.g.
//      "merchant.com.yaronj.tim", and enable Apple Pay on that App ID.
//   3. In the Braintree Control Panel → Processing → Apple Pay, register
//      that merchant ID and upload the Apple Pay Payment Processing
//      Certificate Braintree generates for it.
//   4. Add BRAINTREE_MERCHANT_ID / BRAINTREE_PUBLIC_KEY / BRAINTREE_PRIVATE_KEY
//      / BRAINTREE_ENV ("sandbox" | "production") to functions/.env,
//      mirroring PAYPAL_CLIENT_ID/SECRET.

export class BraintreeNotConfiguredError extends Error {
  constructor() {
    super("Apple Pay is not configured yet");
    this.name = "BraintreeNotConfiguredError";
  }
}

export class BraintreeCurrencyNotSupportedError extends Error {
  constructor(public readonly currency: string) {
    super(`Apple Pay does not support ${currency} yet`);
    this.name = "BraintreeCurrencyNotSupportedError";
  }
}

/**
 * Braintree ties currency to the merchant account, not to the transaction —
 * there is no per-transaction currency field. Charging a currency that
 * doesn't match the merchant account actually in use would silently charge
 * the raw amount in the wrong currency (e.g. an ILS price charged as USD),
 * so this must hard-fail rather than just log a warning.
 */
export function assertCurrencySupported(currency: string): void {
  const defaultCurrency = process.env.BRAINTREE_DEFAULT_CURRENCY;
  const merchantAccountId = process.env.BRAINTREE_MERCHANT_ACCOUNT_ID;
  if (defaultCurrency && currency !== defaultCurrency && !merchantAccountId) {
    throw new BraintreeCurrencyNotSupportedError(currency);
  }
}

function getGateway(): braintree.BraintreeGateway {
  const merchantId = process.env.BRAINTREE_MERCHANT_ID ?? "";
  const publicKey = process.env.BRAINTREE_PUBLIC_KEY ?? "";
  const privateKey = process.env.BRAINTREE_PRIVATE_KEY ?? "";
  if (!merchantId || !publicKey || !privateKey) {
    throw new BraintreeNotConfiguredError();
  }
  return new braintree.BraintreeGateway({
    environment:
      process.env.BRAINTREE_ENV === "production"
        ? braintree.Environment.Production
        : braintree.Environment.Sandbox,
    merchantId,
    publicKey,
    privateKey,
  });
}

export async function generateApplePayClientToken(): Promise<string> {
  const gateway = getGateway();
  // Must match the merchantAccountId used in createBraintreeSale below —
  // the Apple Pay sheet's displayed currency comes from whichever merchant
  // account this client token is scoped to, so a mismatch here means the
  // sheet shows one currency while the sale charges in another.
  const response = await gateway.clientToken.generate({
    merchantAccountId: process.env.BRAINTREE_MERCHANT_ACCOUNT_ID || undefined,
  });
  return response.clientToken;
}

export interface BraintreeSaleParams {
  amountCents: number;
  currency: string;
  nonce: string;
  orderId: string;
}

export interface BraintreeSaleResult {
  success: boolean;
  transactionId: string;
  message?: string;
}

export async function createBraintreeSale(
  params: BraintreeSaleParams
): Promise<BraintreeSaleResult> {
  assertCurrencySupported(params.currency);

  const gateway = getGateway();
  const amount = (params.amountCents / 100).toFixed(2);

  const result = await gateway.transaction.sale({
    amount,
    paymentMethodNonce: params.nonce,
    orderId: params.orderId,
    merchantAccountId: process.env.BRAINTREE_MERCHANT_ACCOUNT_ID || undefined,
    options: { submitForSettlement: true },
  });

  logger.info(
    `[braintree] sale orderId=${params.orderId} success=${result.success} status=${result.transaction?.status}`
  );

  return {
    success: result.success,
    transactionId: result.transaction?.id ?? "",
    message: result.success ? undefined : result.message,
  };
}
