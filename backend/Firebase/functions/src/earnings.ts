import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";

import { Timestamp } from "firebase-admin/firestore";

import { LessonDoc } from "./types";
import { DEFAULT_CURRENCY } from "./pricing";
import { monthKey, nextPayoutFor } from "./payoutSchedule";
import {
  PayoutMethod,
  PayoutMethodValidationError,
  parsePayoutMethod,
  payoutMethodSummary,
  verifiedPayPalPayoutMethod,
} from "./payoutMethod";
import { ISRAELI_BANKS } from "./israeliBanks";
import { lookupPayPalAccountEmail, BraintreeNotConfiguredError } from "./braintree";

const firestore = admin.firestore();

// ─── Teacher earnings ────────────────────────────────────────────────────────
//
// Authoritative, server-side aggregation of what a teacher earned, grouped by
// calendar month with a weekly breakdown, plus when the next payout lands
// (see ./payoutSchedule for the 9th-of-the-following-month rule).
//
// The client renders the returned numbers; every label (month names, week
// labels, dates) is formatted client-side against the viewer's locale, so this
// service deliberately returns raw values and never display strings.

/** Cap on the lessons scanned per teacher — well beyond a realistic history,
 *  but bounds the read cost of a single call. */
const MAX_LESSONS = 2000;

interface WeekBucket {
  index: number;
  startDay: number;
  endDay: number;
  earningsCents: number;
  minutesCount: number;
  lessonCount: number;
}

interface MonthBucket {
  id: string; // "yyyy-MM"
  year: number;
  month: number; // 1-12
  earningsCents: number;
  minutesCount: number;
  lessonCount: number;
  isCurrentMonth: boolean;
  weeks: WeekBucket[];
}

/** `teacherEarnings` on a lesson is stored in major units (e.g. 12.5 ILS). */
function toCents(majorUnits: unknown): number {
  const n = Number(majorUnits);
  return Number.isFinite(n) && n > 0 ? Math.round(n * 100) : 0;
}

function toMinutes(billedSeconds: unknown): number {
  const n = Math.floor(Number(billedSeconds));
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.max(1, Math.round(n / 60));
}

/** Weeks are fixed 7-day spans from the 1st, so the last one runs short —
 *  the same shape the earnings screen has always shown. */
function weekIndexFor(dayOfMonth: number): number {
  return Math.floor((dayOfMonth - 1) / 7) + 1;
}

function daysInMonth(year: number, month: number): number {
  return new Date(Date.UTC(year, month, 0)).getUTCDate();
}

export const teacherEarningsSummary = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const snap = await firestore
    .collection("lessons")
    .where("teacherUid", "==", uid)
    .limit(MAX_LESSONS)
    .get();

  const now = new Date();
  const currentKey = monthKey(now.getUTCFullYear(), now.getUTCMonth() + 1);

  let currency = "";
  const byMonth = new Map<string, MonthBucket>();

  for (const doc of snap.docs) {
    const lesson = doc.data() as LessonDoc;
    // Only settled lessons carry earnings; an in-progress one has none yet.
    const endedAt = lesson.endedAt?.toDate?.();
    if (!endedAt) continue;

    const earningsCents = toCents(lesson.teacherEarnings);
    const minutes = toMinutes(lesson.billedSeconds);

    const year = endedAt.getUTCFullYear();
    const month = endedAt.getUTCMonth() + 1;
    const key = monthKey(year, month);

    if (!currency && typeof lesson.currencyCode === "string" && lesson.currencyCode.trim()) {
      currency = lesson.currencyCode.trim().toUpperCase();
    }

    let bucket = byMonth.get(key);
    if (!bucket) {
      const lastDay = daysInMonth(year, month);
      const weeks: WeekBucket[] = [];
      for (let startDay = 1; startDay <= lastDay; startDay += 7) {
        weeks.push({
          index: weekIndexFor(startDay),
          startDay,
          endDay: Math.min(startDay + 6, lastDay),
          earningsCents: 0,
          minutesCount: 0,
          lessonCount: 0,
        });
      }
      bucket = {
        id: key,
        year,
        month,
        earningsCents: 0,
        minutesCount: 0,
        lessonCount: 0,
        isCurrentMonth: key === currentKey,
        weeks,
      };
      byMonth.set(key, bucket);
    }

    bucket.earningsCents += earningsCents;
    bucket.minutesCount += minutes;
    bucket.lessonCount += 1;

    const week = bucket.weeks[weekIndexFor(endedAt.getUTCDate()) - 1];
    if (week) {
      week.earningsCents += earningsCents;
      week.minutesCount += minutes;
      week.lessonCount += 1;
    }
  }

  const months = [...byMonth.values()].sort((a, b) => a.id.localeCompare(b.id));
  const totalEarningsCents = months.reduce((sum, m) => sum + m.earningsCents, 0);

  const { periodMonthId, payoutDate } = nextPayoutFor(now);
  const pendingAmountCents = byMonth.get(periodMonthId)?.earningsCents ?? 0;

  // Where the money goes — the app shows it so the teacher can confirm it, and
  // offers an edit form backed by updateTeacherPayoutMethod below.
  const userSnap = await firestore.collection("users").doc(uid).get();
  const user = userSnap.data() ?? {};
  const payoutMethod = (user.payoutMethod ?? null) as PayoutMethod | null;

  logger.info(
    `[earnings] teacherEarningsSummary uid=${uid} lessons=${snap.size} months=${months.length} totalCents=${totalEarningsCents} payoutPeriod=${periodMonthId} payoutDate=${payoutDate}`
  );

  return {
    currency: currency || DEFAULT_CURRENCY,
    totalEarningsCents,
    months,
    nextPayment: {
      amountCents: pendingAmountCents,
      payoutDate,
      periodMonthId,
    },
    payoutMethod,
    payoutMethodSummary: payoutMethod ? payoutMethodSummary(payoutMethod) : "",
    // Sent alongside so the app's bank picker always offers exactly the banks
    // this backend will accept.
    banks: ISRAELI_BANKS,
    // The teacher's profile phone, so the Bit form can offer it rather than
    // making them retype a number the app already has.
    profilePhone: typeof user.phoneNumber === "string" ? user.phoneNumber : "",
  };
});

// ─── updateTeacherPayoutMethod ───────────────────────────────────────────────

/** Sets where the teacher's monthly payout is sent. Validates per method type
 *  (see ./payoutMethod) and replaces the stored method outright, so switching
 *  from, say, Bit to a bank account leaves no stale fields behind. */
export const updateTeacherPayoutMethod = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  let method: PayoutMethod;
  try {
    method = parsePayoutMethod((req.data as Record<string, unknown>)?.payoutMethod ?? req.data);
  } catch (err) {
    if (err instanceof PayoutMethodValidationError) {
      logger.info(`[earnings] payout method rejected uid=${uid} reason=${err.message}`);
      throw new HttpsError("invalid-argument", err.message);
    }
    throw err;
  }

  await firestore.collection("users").doc(uid).set(
    { payoutMethod: { ...method, updatedAt: Timestamp.now() } },
    { merge: true }
  );

  logger.info(`[earnings] payout method updated uid=${uid} type=${method.type}`);

  return { payoutMethod: method, payoutMethodSummary: payoutMethodSummary(method) };
});

// ─── verifyPayPalPayoutAccount ───────────────────────────────────────────────

/**
 * Confirms a PayPal payout account and saves it, from a nonce produced by the
 * teacher completing a PayPal login in the app.
 *
 * This is the only path that can mark a PayPal payout method `verified`: the
 * email comes back from PayPal via Braintree rather than from the form, so a
 * teacher cannot claim an address they do not control.
 */
export const verifyPayPalPayoutAccount = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const nonce = (req.data as Record<string, unknown>)?.nonce;
  if (typeof nonce !== "string" || !nonce) {
    throw new HttpsError("invalid-argument", "Missing PayPal nonce");
  }

  let email: string;
  try {
    email = await lookupPayPalAccountEmail(uid, nonce);
  } catch (err) {
    if (err instanceof BraintreeNotConfiguredError) {
      throw new HttpsError("failed-precondition", "PayPal verification is not available yet.");
    }
    logger.error(`[earnings] PayPal payout verification failed uid=${uid}`, err);
    throw new HttpsError("internal", "Could not confirm your PayPal account. Please try again.");
  }

  const method = verifiedPayPalPayoutMethod(email);
  await firestore.collection("users").doc(uid).set(
    { payoutMethod: { ...method, updatedAt: Timestamp.now() } },
    { merge: true }
  );

  logger.info(`[earnings] PayPal payout account verified uid=${uid}`);

  return { payoutMethod: method, payoutMethodSummary: payoutMethodSummary(method) };
});
