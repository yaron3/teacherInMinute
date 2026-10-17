// ─── Sign-up welcome minutes ─────────────────────────────────────────────────
//
// A student gets free minutes as soon as they have an account, whether or not
// they have verified their email yet. It comes on top of the verified-email
// reward (./emailRewards), which still pays out when they verify.
//
// The address is not proven yet, so anyone can make up another one. Two limits
// hold the cost down:
//
//   • once per *mailbox*, using the same canonical address and the same
//     `emailRewardClaims` document as the verified-email reward, in its own
//     `studentSignup` slot — so `me+1@gmail.com` does not earn it again;
//   • a cap on how many students get it in all
//     (`signup_reward_student_slots`), counted in
//     `emailRewardPromotion/studentSignup.granted`.
//
// Anonymous sessions never get it. An anonymous student who signs up keeps
// their uid — the app links the email or provider to the anonymous account —
// so the reward is granted when the profile stops being anonymous rather than
// when the role is first set, which happened back when they started.
//
// Granted from a trigger on the user document rather than from a callable, so
// it reaches every app version already installed: the moment an account first
// becomes a student, it is credited.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import {
  canonicalEmailIdentity,
  EMAIL_REWARD_CLAIMS_COLLECTION,
  EMAIL_REWARD_PROMOTION_COLLECTION,
  emailClaimId,
} from "./emailRewards";
import { normalizeEmail } from "./emailValidation";
import { readRcNumber } from "./remoteConfig";

const firestore = admin.firestore();

/** Slot in `emailRewardClaims/{mailbox}` and document in
 *  `emailRewardPromotion` for this reward. */
export const SIGNUP_REWARD_SLOT = "studentSignup";
/** Purchase document the grant is recorded under. */
export const SIGNUP_REWARD_PURCHASE_ID = "signup_reward";

/** Off until Remote Config says how many minutes to give. */
const DEFAULT_SIGNUP_MINUTES = 0;
/** How many students the minutes are for, when Remote Config does not say. */
const DEFAULT_SIGNUP_SLOTS = 100;

export interface SignupRewardOffer {
  minutes: number;
  slots: number;
}

/** Setting either value to 0 in Remote Config switches the reward off without
 *  a deploy. */
export async function getSignupRewardOffer(): Promise<SignupRewardOffer> {
  const [minutes, slots] = await Promise.all([
    readRcNumber("signup_reward_student_minutes"),
    readRcNumber("signup_reward_student_slots"),
  ]);
  return {
    minutes: wholeCount(minutes, DEFAULT_SIGNUP_MINUTES),
    slots: wholeCount(slots, DEFAULT_SIGNUP_SLOTS),
  };
}

function wholeCount(value: number | undefined, fallback: number): number {
  if (value === undefined) return fallback;
  return Math.max(0, Math.floor(value));
}

/** Students the reward can still go to: the cap less those rewarded. */
export function signupSlotsRemaining(offer: SignupRewardOffer, granted: unknown): number {
  const used = Math.max(0, Math.floor(Number(granted) || 0));
  return Math.max(0, offer.slots - used);
}

/** Whether a user-document write is the account first becoming a student. */
export function becameStudent(beforeRole: unknown, afterRole: unknown): boolean {
  return beforeRole !== "student" && afterRole === "student";
}

/** Whether a user-document write is an anonymous student's profile being
 *  marked registered, after the app linked it to an account. */
export function anonymousStudentRegistered(
  before: { role?: unknown; isAnonymous?: unknown } | undefined,
  after: { role?: unknown; isAnonymous?: unknown } | undefined
): boolean {
  return before?.isAnonymous === true && after?.isAnonymous !== true && after?.role === "student";
}

export type SignupGrantStatus =
  | "granted"
  | "already_granted"
  /** Another account on the same mailbox already took it. */
  | "claimed_by_other_account"
  /** Anonymous, no email, or not a student. */
  | "not_eligible"
  /** Switched off in Remote Config. */
  | "unavailable"
  /** Every slot has been taken. */
  | "promotion_ended";

/** Credits the sign-up minutes to a student account, once per mailbox. */
export async function grantSignupRewardFor(uid: string): Promise<SignupGrantStatus> {
  const userRef = firestore.collection("users").doc(uid);
  const promotionRef = firestore.collection(EMAIL_REWARD_PROMOTION_COLLECTION).doc(SIGNUP_REWARD_SLOT);
  const [authUser, offer] = await Promise.all([admin.auth().getUser(uid), getSignupRewardOffer()]);

  if (offer.minutes <= 0 || offer.slots <= 0) return "unavailable";
  // An anonymous account has no provider; it has no email either, but say so.
  const email = normalizeEmail(authUser.email);
  if (authUser.providerData.length === 0 || !email) return "not_eligible";
  const canonical = canonicalEmailIdentity(email);
  if (!canonical) return "not_eligible";
  const claimRef = firestore.collection(EMAIL_REWARD_CLAIMS_COLLECTION).doc(emailClaimId(canonical));

  return firestore.runTransaction(async (tx): Promise<SignupGrantStatus> => {
    const [claimSnap, userSnap, promotionSnap] = await Promise.all([
      tx.get(claimRef),
      tx.get(userRef),
      tx.get(promotionRef),
    ]);
    if (userSnap.data()?.role !== "student") return "not_eligible";
    if (userSnap.data()?.emailRewards?.[SIGNUP_REWARD_SLOT]) return "already_granted";
    const existing = claimSnap.data()?.[SIGNUP_REWARD_SLOT] as { uid?: string } | undefined;
    if (existing) {
      return existing.uid === uid ? "already_granted" : "claimed_by_other_account";
    }
    if (signupSlotsRemaining(offer, promotionSnap.data()?.granted) <= 0) return "promotion_ended";

    const now = Timestamp.now();
    const minutes = offer.minutes;
    tx.set(claimRef, { [SIGNUP_REWARD_SLOT]: { uid, claimedAt: now } }, { merge: true });
    tx.set(promotionRef, { granted: FieldValue.increment(1), updatedAt: now }, { merge: true });
    tx.set(
      userRef,
      {
        remainingMinutes: FieldValue.increment(minutes),
        totalMinutes: FieldValue.increment(minutes),
        emailRewards: { [SIGNUP_REWARD_SLOT]: { minutes, grantedAt: now } },
      },
      { merge: true }
    );
    // `provider: "email_reward"` so the app counts it, like the verified-email
    // minutes, as free minutes rather than a purchase (HistoryModel).
    tx.set(userRef.collection("purchases").doc(SIGNUP_REWARD_PURCHASE_ID), {
      pricingOptionId: SIGNUP_REWARD_PURCHASE_ID,
      provider: "email_reward",
      amountCents: 0,
      currency: "USD",
      type: "pay_as_you_go",
      status: "active",
      purchasedAt: now,
      updatedAt: now,
      minutesPurchased: minutes,
      minutesRemaining: minutes,
      minutesUsed: 0,
    });
    return "granted";
  });
}

export const onStudentSignup = onDocumentWritten("users/{uid}", async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!becameStudent(before?.role, after?.role) && !anonymousStudentRegistered(before, after)) return;

  const uid = event.params.uid;
  try {
    const status = await grantSignupRewardFor(uid);
    logger.info(`[signupRewards] uid=${uid} status=${status}`);
  } catch (err) {
    // Never fail the write that triggered this.
    logger.error(`[signupRewards] grant failed uid=${uid}`, err);
  }
});
