// ─── Verified-email welcome rewards ──────────────────────────────────────────
//
// A user who proves they own their email gets a one-off welcome reward for the
// role they signed up as:
//
//   • student — free minutes, credited like a purchase so lessons consume them
//     through the ordinary purchase path.
//   • teacher — a better share (default 100%) on their first taught minutes,
//     applied at lesson settlement (see ./lessons and ./billing).
//
// Each reward is given once per *mailbox*, not once per account. Otherwise the
// same person collects it again with `me+1@gmail.com`, `m.e@gmail.com` or by
// deleting and recreating their account. Claims are stored in
// `emailRewardClaims/{sha256(canonical email)}`, one slot per role, and that
// document outlives the account on purpose.
//
// "Proves they own it" is ./emailOwnership: a verified email/password address,
// or an address a federated provider (Google, Apple) vouched for. The server
// reads the auth record itself, so the app never has to refresh its token for
// a newly verified address to count.

import { createHash } from "node:crypto";

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { domainOf, normalizeEmail } from "./emailValidation";
import { provenEmailsFor } from "./emailOwnership";
import { readRcNumber } from "./remoteConfig";

const firestore = admin.firestore();

export const EMAIL_REWARD_CLAIMS_COLLECTION = "emailRewardClaims";
/** Purchase document the student grant is recorded under. */
export const STUDENT_REWARD_PURCHASE_ID = "email_verification_reward";

const DEFAULT_STUDENT_MINUTES = 30;
const DEFAULT_TEACHER_SHARE = 1;
const DEFAULT_TEACHER_BONUS_MINUTES = 300;

export type RewardRole = "student" | "teacher";

// ─── Canonical mailbox ───────────────────────────────────────────────────────

/** Domains that are the same Gmail mailbox under another name. */
const GMAIL_DOMAINS = new Set(["gmail.com", "googlemail.com"]);

/**
 * The mailbox an address actually delivers to, so aliases of one inbox compare
 * equal:
 *
 *   • case and surrounding whitespace are ignored;
 *   • `+tag` subaddressing is dropped for every domain — Gmail, Outlook,
 *     iCloud, Proton and Fastmail all deliver `me+x@` to `me@`, and two real
 *     people on one domain differing only by a `+tag` does not happen in
 *     practice;
 *   • dots are dropped only for Gmail, the one large provider that ignores
 *     them. Elsewhere `j.doe@` and `jdoe@` can be different people;
 *   • `googlemail.com` is folded into `gmail.com`.
 *
 * Returns "" for anything without both a local part and a domain.
 */
export function canonicalEmailIdentity(raw: unknown): string {
  const email = normalizeEmail(raw);
  const at = email.lastIndexOf("@");
  if (at <= 0 || at === email.length - 1) return "";

  let local = email.slice(0, at);
  let domain = domainOf(email);

  const plus = local.indexOf("+");
  // A local part that *starts* with "+" has no base to fall back to; keep it
  // whole rather than collapsing every such address into one empty name.
  if (plus > 0) local = local.slice(0, plus);

  if (GMAIL_DOMAINS.has(domain)) {
    domain = "gmail.com";
    const undotted = local.replace(/\./g, "");
    if (undotted) local = undotted;
  }

  return `${local}@${domain}`;
}

/** Document id for a mailbox's claims. Hashed so the collection holds no
 *  plaintext addresses and no address character can break a document path. */
export function emailClaimId(canonicalEmail: string): string {
  return createHash("sha256").update(canonicalEmail).digest("hex");
}

// ─── Offer (Remote Config) ───────────────────────────────────────────────────

export interface EmailRewardOffer {
  studentMinutes: number;
  teacherShare: number;
  teacherBonusMinutes: number;
}

/** Setting a value to 0 in Remote Config switches that reward off without a
 *  deploy: nothing is claimed, so it can be switched back on later. */
export async function getEmailRewardOffer(): Promise<EmailRewardOffer> {
  const [studentMinutes, teacherShare, teacherBonusMinutes] = await Promise.all([
    readRcNumber("email_reward_student_minutes"),
    readRcNumber("email_reward_teacher_share"),
    readRcNumber("email_reward_teacher_minutes"),
  ]);
  return {
    studentMinutes: wholeMinutes(studentMinutes, DEFAULT_STUDENT_MINUTES),
    teacherShare:
      teacherShare !== undefined && teacherShare > 0 && teacherShare <= 1
        ? teacherShare
        : DEFAULT_TEACHER_SHARE,
    teacherBonusMinutes: wholeMinutes(teacherBonusMinutes, DEFAULT_TEACHER_BONUS_MINUTES),
  };
}

function wholeMinutes(value: number | undefined, fallback: number): number {
  if (value === undefined) return fallback;
  return Math.max(0, Math.floor(value));
}

function offerIsActive(role: RewardRole, offer: EmailRewardOffer): boolean {
  return role === "student" ? offer.studentMinutes > 0 : offer.teacherBonusMinutes > 0;
}

// ─── Teacher bonus on the user document ──────────────────────────────────────

/** `users/{uid}.teacherBonus`. The share is frozen at grant time so a later
 *  Remote Config change never alters a bonus a teacher already holds. */
export interface TeacherBonus {
  share: number;
  minutesGranted: number;
  minutesRemaining: number;
  grantedAt: Timestamp;
}

/** The usable part of a stored bonus, or undefined when there is none left. */
export function readTeacherBonus(
  value: unknown
): { share: number; minutesRemaining: number } | undefined {
  if (!value || typeof value !== "object") return undefined;
  const bonus = value as Partial<TeacherBonus>;
  const share = Number(bonus.share);
  const minutesRemaining = Math.max(0, Math.floor(Number(bonus.minutesRemaining) || 0));
  if (!Number.isFinite(share) || share <= 0 || share > 1) return undefined;
  if (minutesRemaining <= 0) return undefined;
  return { share, minutesRemaining };
}

// ─── claimEmailReward ────────────────────────────────────────────────────────

export type ClaimStatus =
  /** The reward was credited by this call. */
  | "granted"
  /** This account already has it — calling again is harmless. */
  | "already_granted"
  /** The address is not proven yet; the app should offer to (re)send the link. */
  | "not_verified"
  /** Another account on the same mailbox already took this role's reward. */
  | "claimed_by_other_account"
  /** No role chosen yet, or no email on the account. */
  | "not_eligible"
  /** The reward is switched off in Remote Config. */
  | "unavailable";

/**
 * Claims the welcome reward for the caller's current role, if they have earned
 * it. Idempotent and cheap, so the apps call it whenever a home screen opens:
 * a Google or Apple user is rewarded without doing anything, and an email user
 * is rewarded on the first open after following the link.
 *
 * Every response carries the offer amounts, so the app can describe the reward
 * to a user who has not verified yet.
 */
export const claimEmailReward = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const userRef = firestore.collection("users").doc(uid);
  const [authUser, userSnap, offer] = await Promise.all([
    admin.auth().getUser(uid),
    userRef.get(),
    getEmailRewardOffer(),
  ]);

  const role = userSnap.data()?.role;
  const email = normalizeEmail(authUser.email);
  const respond = (status: ClaimStatus, extra: Record<string, unknown> = {}) => ({
    status,
    role: role === "student" || role === "teacher" ? role : null,
    studentMinutes: offer.studentMinutes,
    teacherShare: offer.teacherShare,
    teacherBonusMinutes: offer.teacherBonusMinutes,
    teacherBonusMinutesRemaining:
      readTeacherBonus(userSnap.data()?.teacherBonus)?.minutesRemaining ?? 0,
    ...extra,
  });

  if ((role !== "student" && role !== "teacher") || !email) {
    return respond("not_eligible");
  }
  if (userSnap.data()?.emailRewards?.[role]) {
    return respond("already_granted");
  }
  if (!offerIsActive(role, offer)) {
    return respond("unavailable");
  }
  if (!provenEmailsFor(authUser).has(email)) {
    return respond("not_verified");
  }

  const canonical = canonicalEmailIdentity(email);
  if (!canonical) return respond("not_eligible");
  const claimRef = firestore.collection(EMAIL_REWARD_CLAIMS_COLLECTION).doc(emailClaimId(canonical));

  const status = await firestore.runTransaction(async (tx): Promise<ClaimStatus> => {
    const [claimSnap, freshUser] = await Promise.all([tx.get(claimRef), tx.get(userRef)]);
    const existing = claimSnap.data()?.[role] as { uid?: string } | undefined;
    if (existing) {
      return existing.uid === uid ? "already_granted" : "claimed_by_other_account";
    }
    if (freshUser.data()?.emailRewards?.[role]) return "already_granted";

    const now = Timestamp.now();
    tx.set(claimRef, { [role]: { uid, claimedAt: now } }, { merge: true });

    if (role === "student") {
      const minutes = offer.studentMinutes;
      tx.set(
        userRef,
        {
          remainingMinutes: FieldValue.increment(minutes),
          totalMinutes: FieldValue.increment(minutes),
          emailRewards: { student: { minutes, grantedAt: now } },
        },
        { merge: true }
      );
      tx.set(userRef.collection("purchases").doc(STUDENT_REWARD_PURCHASE_ID), {
        pricingOptionId: STUDENT_REWARD_PURCHASE_ID,
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
    } else {
      const bonus: TeacherBonus = {
        share: offer.teacherShare,
        minutesGranted: offer.teacherBonusMinutes,
        minutesRemaining: offer.teacherBonusMinutes,
        grantedAt: now,
      };
      tx.set(
        userRef,
        {
          teacherBonus: bonus,
          emailRewards: {
            teacher: { share: bonus.share, minutes: bonus.minutesGranted, grantedAt: now },
          },
        },
        { merge: true }
      );
    }
    return "granted";
  });

  logger.info(`[emailRewards] claim uid=${uid} role=${role} status=${status}`);

  if (status !== "granted") return respond(status);
  return respond(status, {
    minutesAdded: role === "student" ? offer.studentMinutes : 0,
    teacherBonusMinutesRemaining: role === "teacher" ? offer.teacherBonusMinutes : 0,
  });
});
