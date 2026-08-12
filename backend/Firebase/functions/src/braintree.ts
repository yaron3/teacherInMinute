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
 * so every chargeable currency names its own account, one env var each:
 *
 *   BRAINTREE_MERCHANT_ACCOUNT_ILS=my_ils_account
 *   BRAINTREE_MERCHANT_ACCOUNT_USD=my_usd_account
 *
 * Adding a currency is then a Control Panel account plus one line in
 * functions/.env. An undeclared currency hard-fails rather than falling back
 * to the gateway's default account, which is what would produce the
 * wrong-currency charge. A declared-but-empty value means "the gateway's
 * default account" — only correct for the one currency that account is
 * actually denominated in. Braintree cannot verify that an id really matches
 * the currency it is mapped to here, so check each pairing in the Control
 * Panel yourself.
 */
export function merchantAccountIdFor(currency: string): string | undefined {
  const id = process.env[`BRAINTREE_MERCHANT_ACCOUNT_${currency.toUpperCase()}`];
  if (id === undefined) {
    throw new BraintreeCurrencyNotSupportedError(currency);
  }
  return id.trim() || undefined;
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

export async function generateBraintreeClientToken(currency: string): Promise<string> {
  const gateway = getGateway();
  // Must match the merchantAccountId used in createBraintreeSale below — the
  // wallet sheet's displayed currency (Apple Pay or Google Pay) comes from
  // whichever merchant account this client token is scoped to, so a mismatch
  // here means the sheet shows one currency while the sale charges in another.
  const response = await gateway.clientToken.generate({
    merchantAccountId: merchantAccountIdFor(currency),
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
  const merchantAccountId = merchantAccountIdFor(params.currency);

  const gateway = getGateway();
  const amount = (params.amountCents / 100).toFixed(2);

  const result = await gateway.transaction.sale({
    amount,
    paymentMethodNonce: params.nonce,
    orderId: params.orderId,
    merchantAccountId,
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
