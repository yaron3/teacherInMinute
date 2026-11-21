import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import { CONNECTION_FEE_CENTS } from "./types";
import { readRcNumber } from "./remoteConfig";

const firestore = admin.firestore();

export const DEFAULT_CURRENCY = "ILS";
export const USD = "USD";

const DEFAULT_PRICE_PER_MINUTE_USD = 0.5;
const DEFAULT_PRICE_PER_MINUTE_ILS = 2.0;
const DEFAULT_EXCHANGE_RATE_ILS = 4.0;
const DEFAULT_TEACHER_SHARE = 0.75;
const DEFAULT_TEACHER_RATE_PER_MINUTE_ILS = 2;

export interface ResolvedPricing {
  currency: string;
  pricePerMinute: number;
  exchangeRateToUsd: number;
  teacherShare: number;
}

function normalizeCurrencyCode(value: unknown): string {
  if (typeof value !== "string") return DEFAULT_CURRENCY;
  const trimmed = value.trim().toUpperCase();
  return trimmed.length === 3 ? trimmed : DEFAULT_CURRENCY;
}

export async function getStudentCurrency(studentUid: string): Promise<string> {
  try {
    const snap = await firestore.collection("users").doc(studentUid).get();
    return normalizeCurrencyCode(snap.data()?.currency);
  } catch (error) {
    logger.warn(`[pricing] failed reading currency for uid=${studentUid}`, error);
    return DEFAULT_CURRENCY;
  }
}

function defaultPricePerMinute(currency: string): number | undefined {
  if (currency === USD) return DEFAULT_PRICE_PER_MINUTE_USD;
  if (currency === "ILS") return DEFAULT_PRICE_PER_MINUTE_ILS;
  return undefined;
}

function defaultExchangeRate(currency: string): number | undefined {
  if (currency === USD) return 1;
  if (currency === "ILS") return DEFAULT_EXCHANGE_RATE_ILS;
  return undefined;
}

export async function getExchangeRateToUsd(currency: string): Promise<number> {
  if (currency === USD) return 1;
  const rcKey = `exchange_rate_${currency.toLowerCase()}`;
  const fromRc = await readRcNumber(rcKey);
  if (fromRc !== undefined && fromRc > 0) return fromRc;
  const fallback = defaultExchangeRate(currency);
  if (fallback !== undefined) return fallback;
  throw new Error(`No exchange rate configured for currency ${currency}`);
}

export async function getPricePerMinute(currency: string): Promise<number> {
  const rcKey = `price_per_minute_${currency.toLowerCase()}`;
  const native = await readRcNumber(rcKey);
  if (native !== undefined && native > 0) return native;

  if (currency === USD) {
    const fallback = defaultPricePerMinute(USD);
    if (fallback === undefined) {
      throw new Error("price_per_minute_usd missing in Remote Config and no default");
    }
    return fallback;
  }

  const usdPrice = await readRcNumber("price_per_minute_usd")
    ?? defaultPricePerMinute(USD);
  if (usdPrice === undefined || usdPrice <= 0) {
    throw new Error("price_per_minute_usd missing — cannot derive other currencies");
  }
  const rate = await getExchangeRateToUsd(currency);
  return Math.round(usdPrice * rate * 100) / 100;
}

/** The one-off fee charged when a lesson connects, in cents of the student's
 *  currency. Source of truth is Remote Config `connection_fee_cents`, which the
 *  apps read too — so the fee the student is quoted on the home screen is the
 *  same number this backend bills. Falls back to the built-in constant when the
 *  key is absent. */
export async function getConnectionFeeCents(): Promise<number> {
  const fromRc = await readRcNumber("connection_fee_cents");
  if (fromRc !== undefined && fromRc >= 0) return Math.round(fromRc);
  return CONNECTION_FEE_CENTS;
}

export async function getTeacherShare(): Promise<number> {
  const fromRc = await readRcNumber("teacher_share");
  if (fromRc !== undefined && fromRc > 0 && fromRc <= 1) return fromRc;
  return DEFAULT_TEACHER_SHARE;
}

/** A per-teacher rate in ILS, or undefined when none usable is set. */
export function readTeacherRateIls(value: unknown): number | undefined {
  return typeof value === "number" && Number.isFinite(value) && value > 0 ? value : undefined;
}

/** Catches a mistyped per-minute rate before it is paid out. */
export const MAX_TEACHER_RATE_ILS = 100;

/**
 * A rate as the admin console submits it: rounded to agorot, or `null` to
 * return the teacher to the default. `undefined` means it is not acceptable.
 */
export function parseAdminTeacherRate(value: unknown): number | null | undefined {
  if (value === null) return null;
  const rate = readTeacherRateIls(value);
  if (rate === undefined || rate > MAX_TEACHER_RATE_ILS) return undefined;
  const rounded = Math.round(rate * 100) / 100;
  return rounded > 0 ? rounded : undefined;
}

/**
 * What a teacher is paid per billed minute, in major units of `currency`.
 *
 * The rate is independent of the student's price: the teacher's own
 * `teacherRatePerMinuteIls` when the admin console set one, otherwise Remote
 * Config `teacher_rate_per_minute_ils`. Rates are held in ILS and converted
 * for a lesson billed in another currency.
 */
export async function resolveTeacherRatePerMinute(
  teacher: { teacherRatePerMinuteIls?: unknown } | undefined,
  currency: string
): Promise<number> {
  const ownRate = readTeacherRateIls(teacher?.teacherRatePerMinuteIls);
  const rateIls =
    ownRate ??
    readTeacherRateIls(await readRcNumber("teacher_rate_per_minute_ils")) ??
    DEFAULT_TEACHER_RATE_PER_MINUTE_ILS;
  if (currency === "ILS") return rateIls;
  const [ilsPerUsd, currencyPerUsd] = await Promise.all([
    getExchangeRateToUsd("ILS"),
    getExchangeRateToUsd(currency),
  ]);
  return Math.round((rateIls / ilsPerUsd) * currencyPerUsd * 100) / 100;
}

export async function resolvePricingForStudent(studentUid: string): Promise<ResolvedPricing> {
  const currency = await getStudentCurrency(studentUid);
  const [pricePerMinute, exchangeRateToUsd, teacherShare] = await Promise.all([
    getPricePerMinute(currency),
    getExchangeRateToUsd(currency),
    getTeacherShare(),
  ]);
  return { currency, pricePerMinute, exchangeRateToUsd, teacherShare };
}
