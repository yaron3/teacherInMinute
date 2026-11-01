import { createHmac, randomBytes, timingSafeEqual } from "crypto";
import { logger } from "firebase-functions";

// ─── Tranzila — Israeli card acquirer ────────────────────────────────────────
//
// Card checkout runs in two steps so that no card number ever reaches our
// servers and the amount is never trusted from the browser:
//
//   1. Our hosted page (`tranzilaCardCheckout` in ./payments.ts) renders
//      Tranzila Hosted Fields. They validate the card (J2, no money moves)
//      and return a token for it. The validation runs against a handshake
//      (`createHandshake`) that locks the package price on Tranzila's side.
//   2. The page posts that token to `tranzilaCharge`, which debits the price
//      read from the checkout doc through the Transactions API
//      (`createCardTransaction`).
//
// Apple Pay and Google Pay run on the same page, but their wallets only
// support a direct charge (no token), so Tranzila takes the money itself and
// the browser's word that it did is worth nothing. Minutes are credited only
// on Tranzila's server-to-server notification (`tranzilaNotify`), whose URL is
// set on the terminal in my.tranzila — never sent to the browser — and carries
// TRANZILA_NOTIFY_KEY.
//
// Docs:
//   https://docs.tranzila.com/docs/payments-and-billing/authentication
//   https://docs.tranzila.com/docs/payments-and-billing/handshake-v2
//   https://docs.tranzila.com/docs/payments-and-billing/hosted-fields
//   https://docs.tranzila.com/docs/payments-and-billing/tranzila-transactions-api-1/create-a-credit-card-transaction
//
// Config (functions/.env):
//   TRANZILA_APP_KEY, TRANZILA_SECRET — API key pair from my.tranzila
//   TRANZILA_TERMINAL_NAME            — the terminal charges run on
//   TRANZILA_VAT_PERCENT              — optional; VAT included in the price,
//                                       reported on the transaction's item
//   TRANZILA_WALLETS                  — which wallets Tranzila runs, e.g.
//                                       "apple_pay,google_pay"; others stay
//                                       on Braintree's native sheets
//   TRANZILA_NOTIFY_KEY               — secret in the terminal's notify URL
//   TRANZILA_PAGE_BASE_URL            — origin serving the checkout page; for
//                                       Apple Pay, the Hosting domain
//                                       registered with Tranzila
// The terminal needs the Token module and Handshake enabled; Apple Pay also
// needs Tranzila's Apple Pay service and the domain verification file.

const API_BASE = "https://api.tranzila.com";

/** Currencies Hosted Fields accept. */
const SUPPORTED_CURRENCIES = ["ILS", "USD", "EUR"];

export class TranzilaNotConfiguredError extends Error {
  constructor() {
    super("Tranzila is not configured");
    this.name = "TranzilaNotConfiguredError";
  }
}

/** Tranzila answered and refused the request — a decline or a request error.
 *  Anything else thrown (network, timeout) leaves the outcome unknown. */
export class TranzilaApiError extends Error {
  constructor(public errorCode: number, message: string) {
    super(`Tranzila error ${errorCode}: ${message}`);
    this.name = "TranzilaApiError";
  }
}

/** Origin the checkout page is served from. Apple Pay only runs on a domain
 *  registered for it, which cloudfunctions.net cannot be, so production
 *  points this at Firebase Hosting (rewrites in firebase.json). */
export function tranzilaPageBaseUrl(fallback: string): string {
  return (process.env.TRANZILA_PAGE_BASE_URL || fallback).replace(/\/+$/, "");
}

export function tranzilaTerminalName(): string {
  return process.env.TRANZILA_TERMINAL_NAME ?? "";
}

/** Card payments route to Tranzila only once every credential is filled in;
 *  until then they keep going through PayPal Card Fields. */
export function isTranzilaConfigured(): boolean {
  return Boolean(
    process.env.TRANZILA_APP_KEY && process.env.TRANZILA_SECRET && tranzilaTerminalName()
  );
}

export type TranzilaWallet = "apple_pay" | "google_pay";

/** A wallet runs through Tranzila only when it is listed in TRANZILA_WALLETS
 *  and the notify key that proves its payments is set. */
export function isTranzilaWalletEnabled(wallet: TranzilaWallet): boolean {
  const listed = (process.env.TRANZILA_WALLETS ?? "")
    .split(",")
    .map((w) => w.trim())
    .includes(wallet);
  return listed && isTranzilaConfigured() && Boolean(process.env.TRANZILA_NOTIFY_KEY);
}

/** Checks the key Tranzila's notify call carries, in constant time. */
export function isValidNotifyKey(key: unknown): boolean {
  const expected = process.env.TRANZILA_NOTIFY_KEY ?? "";
  if (!expected || typeof key !== "string") return false;
  const a = Buffer.from(key);
  const b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

export interface TranzilaNotification {
  success: boolean;
  amount?: number;
  transactionId?: string;
  thtk?: string;
  checkoutId?: string;
  tranMode?: string;
}

const UUID_PATTERN = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

function firstValue(...values: unknown[]): string | undefined {
  for (const v of values) {
    if (typeof v === "string" && v.trim()) return v.trim();
    if (typeof v === "number" && Number.isFinite(v)) return String(v);
  }
  return undefined;
}

/**
 * Reads a notify payload. Tranzila documents no field list for it, so this
 * accepts both the classic form names (Response, sum, index, tranmode) and the
 * Hosted Fields JSON ones (transaction_response.*), and finds our checkout
 * from the handshake's `request_params`, a `checkout_id` field, the `pdesc`
 * the page sends, or the handshake token.
 */
export function parseTranzilaNotification(payload: Record<string, unknown>): TranzilaNotification {
  const txn = (payload.transaction_response ?? {}) as Record<string, unknown>;
  const requestParams = (payload.request_params ?? {}) as Record<string, unknown>;

  const response = firstValue(payload.Response, payload.processor_response_code, txn.processor_response_code);
  const flag = payload.success ?? txn.success;
  const success = response === "000" || flag === true || flag === "true";

  const amountText = firstValue(payload.sum, payload.amount, txn.amount);
  const amount = amountText !== undefined ? Number(amountText) : undefined;

  const checkoutId =
    firstValue(requestParams.checkout_id, payload.checkout_id, payload.checkoutId) ??
    firstValue(payload.pdesc, txn.pdesc)?.match(UUID_PATTERN)?.[0];

  return {
    success,
    amount: amount !== undefined && Number.isFinite(amount) ? amount : undefined,
    transactionId: firstValue(payload.index, payload.transaction_id, txn.transaction_id, payload.ConfirmationCode),
    thtk: firstValue(payload.thtk, txn.thtk),
    checkoutId,
    tranMode: firstValue(payload.tranmode, payload.tran_mode, txn.tran_mode),
  };
}

export function tranzilaSupportsCurrency(currency: string): boolean {
  return SUPPORTED_CURRENCIES.includes(currency.toUpperCase());
}

/**
 * The four auth headers every API call carries. The access token is
 * HMAC-SHA256 over the app key, keyed with secret + request time + nonce —
 * PHP's `hash_hmac('sha256', $appKey, $secret . $time . $nonce)` in the docs.
 */
export function authHeaders(
  appKey: string,
  secret: string,
  nowSeconds: number = Math.floor(Date.now() / 1000),
  nonce: string = randomBytes(40).toString("hex")
): Record<string, string> {
  const time = String(nowSeconds);
  const accessToken = createHmac("sha256", secret + time + nonce).update(appKey).digest("hex");
  return {
    "X-tranzila-api-app-key": appKey,
    "X-tranzila-api-request-time": time,
    "X-tranzila-api-nonce": nonce,
    "X-tranzila-api-access-token": accessToken,
  };
}

async function post<T extends { error_code?: number; message?: string }>(
  path: string,
  body: Record<string, unknown>
): Promise<T> {
  const appKey = process.env.TRANZILA_APP_KEY ?? "";
  const secret = process.env.TRANZILA_SECRET ?? "";
  if (!appKey || !secret) throw new TranzilaNotConfiguredError();

  const res = await fetch(`${API_BASE}${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...authHeaders(appKey, secret) },
    body: JSON.stringify(body),
  });

  const text = await res.text();
  let json: T;
  try {
    json = JSON.parse(text) as T;
  } catch {
    // Not Tranzila's answer (a proxy or gateway page), so it says nothing
    // about whether the call went through — deliberately not a TranzilaApiError.
    throw new Error(`Tranzila HTTP ${res.status}, non-JSON response: ${text.slice(0, 200)}`);
  }
  // A 200 can still carry an application error, so error_code decides.
  if (!res.ok || json.error_code !== 0) {
    throw new TranzilaApiError(json.error_code ?? res.status, json.message ?? `HTTP ${res.status}`);
  }
  return json;
}

/** Creates a handshake token (`thtk`) that locks `amountCents` for the Hosted
 *  Fields call. Valid for 20 minutes. */
export async function createHandshake(params: {
  amountCents: number;
  checkoutId: string;
}): Promise<string> {
  const terminal = tranzilaTerminalName();
  if (!terminal) throw new TranzilaNotConfiguredError();
  const json = await post<{ error_code: number; message: string; thtk?: string }>(
    "/v2/handshake/create",
    {
      terminal_name: terminal,
      sum: params.amountCents / 100,
      request_params: { checkout_id: params.checkoutId },
    }
  );
  if (!json.thtk) throw new TranzilaApiError(json.error_code, "handshake returned no thtk");
  return json.thtk;
}

export interface TranzilaChargeParams {
  /** Card token from Hosted Fields — never a raw card number. */
  token: string;
  expireMonth: number;
  expireYear: number;
  amountCents: number;
  currency: string;
  description: string;
  checkoutId: string;
  uid: string;
}

export interface TranzilaChargeResult {
  transactionId: string;
  authNumber: string;
  last4?: string;
}

/** Debits a tokenized card through the Transactions API. */
export async function createCardTransaction(
  params: TranzilaChargeParams
): Promise<TranzilaChargeResult> {
  const terminal = tranzilaTerminalName();
  if (!terminal) throw new TranzilaNotConfiguredError();

  const vatPercent = Number(process.env.TRANZILA_VAT_PERCENT);
  const item: Record<string, unknown> = {
    name: params.description,
    type: "I",
    unit_price: params.amountCents / 100,
    units_number: 1,
    // Package prices are what the buyer pays, VAT included.
    price_type: "G",
    ...(Number.isFinite(vatPercent) && process.env.TRANZILA_VAT_PERCENT
      ? { vat_percent: vatPercent }
      : {}),
  };

  const json = await post<{
    error_code: number;
    message: string;
    transaction_result?: {
      processor_response_code?: string;
      transaction_id?: number;
      auth_number?: string;
      last_4?: string;
    };
  }>("/v1/transaction/credit_card/create", {
    terminal_name: terminal,
    txn_type: "debit",
    txn_currency_code: params.currency.toUpperCase(),
    card_number: params.token,
    expire_month: params.expireMonth,
    expire_year: params.expireYear,
    items: [item],
    payment_plan: 1,
    pan_entry_mode: 52,
    remarks: `checkout ${params.checkoutId}`,
    created_by_system: "teacher-in-a-moment",
  });

  const result = json.transaction_result;
  if (!result?.transaction_id || result.processor_response_code !== "000") {
    throw new TranzilaApiError(
      json.error_code,
      `declined processor_response_code=${result?.processor_response_code ?? "(none)"}`
    );
  }

  logger.info(
    `[tranzila] charged checkoutId=${params.checkoutId} uid=${params.uid} transactionId=${result.transaction_id}`
  );
  return {
    transactionId: String(result.transaction_id),
    authNumber: result.auth_number ?? "",
    last4: result.last_4,
  };
}
