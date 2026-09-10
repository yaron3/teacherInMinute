import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import { CONNECTION_FEE_CENTS } from "./types";

const firestore = admin.firestore();

export const DEFAULT_CURRENCY = "ILS";
export const USD = "USD";

const DEFAULT_PRICE_PER_MINUTE_USD = 0.5;
const DEFAULT_PRICE_PER_MINUTE_ILS = 2.0;
const DEFAULT_EXCHANGE_RATE_ILS = 4.0;
const DEFAULT_TEACHER_SHARE = 0.75;

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

// Every readRcNumber used to pull the whole Remote Config template over the
// network — a fresh HTTP round trip per key, so resolvePricingForStudent alone
// fetched it three times and createQuestion paid for one on the ask path. The
// template changes when someone edits it in the console, which is rare next to
// how often these run, so an instance holds it briefly and re-reads after that.
const RC_TEMPLATE_TTL_MS = 60_000;
let rcTemplateCache: { template: admin.remoteConfig.RemoteConfigTemplate; fetchedAt: number } | undefined;
let rcTemplateInFlight: Promise<admin.remoteConfig.RemoteConfigTemplate> | undefined;

async function getRcTemplate(): Promise<admin.remoteConfig.RemoteConfigTemplate> {
  if (rcTemplateCache && Date.now() - rcTemplateCache.fetchedAt < RC_TEMPLATE_TTL_MS) {
    return rcTemplateCache.template;
  }
  // Concurrent callers share one fetch rather than each starting their own.
  if (!rcTemplateInFlight) {
    rcTemplateInFlight = admin
      .remoteConfig()
      .getTemplate()
      .then((template) => {
        rcTemplateCache = { template, fetchedAt: Date.now() };
        return template;
      })
      .finally(() => {
        rcTemplateInFlight = undefined;
      });
  }
  return rcTemplateInFlight;
}

async function readRcNumber(key: string): Promise<number | undefined> {
  try {
    const template = await getRcTemplate();
    const param = template.parameters?.[key] as
      | { defaultValue?: { value?: string } }
      | undefined;
    const raw = param?.defaultValue?.value;
    if (raw == null) return undefined;
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : undefined;
  } catch (error) {
    logger.warn(`[pricing] failed reading Remote Config ${key}`, error);
    return undefined;
  }
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

export async function resolvePricingForStudent(studentUid: string): Promise<ResolvedPricing> {
  const currency = await getStudentCurrency(studentUid);
  const [pricePerMinute, exchangeRateToUsd, teacherShare] = await Promise.all([
    getPricePerMinute(currency),
    getExchangeRateToUsd(currency),
    getTeacherShare(),
  ]);
  return { currency, pricePerMinute, exchangeRateToUsd, teacherShare };
}
