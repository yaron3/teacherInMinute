// ─── Inbox messages ──────────────────────────────────────────────────────────
//
// What the apps' bell lists: `users/{uid}/incomingMessages`, until now written
// only from the admin panel. Signing up, the verification email and the
// welcome rewards each leave one here too (IT-51), so a user who dismissed a
// dialog, or never saw one, can still read what happened to their account.
//
// The writers below run where the language the user reads in is not always
// known (the sign-up reward is granted by a Firestore trigger), so every
// message carries both languages: `title` / `text` in English, as the admin
// panel's messages do, and `titleHe` / `textHe`, which the app shows instead
// when it is in Hebrew.
//
// Each kind has a fixed document id, so a message is never listed twice: a
// resent verification email replaces the earlier note, and a reward can only
// be granted once anyway.

import { Timestamp } from "firebase-admin/firestore";

import type { RewardRole } from "./emailRewards";

export interface InboxMessage {
  title: string;
  text: string;
  titleHe: string;
  textHe: string;
}

export const INBOX_COLLECTION = "incomingMessages";

/** Fixed ids, one per kind of message. */
export const INBOX_MESSAGE_IDS = {
  verificationSent: "account-verification-email",
  emailReward: "account-email-reward",
  signupMinutes: "account-signup-minutes",
} as const;

/** The stored document: the message, when it was written, and what it is. */
export function inboxDocument(kind: keyof typeof INBOX_MESSAGE_IDS, message: InboxMessage): Record<string, unknown> {
  return { ...message, kind, createdAt: Timestamp.now() };
}

function percent(share: number): number {
  return Math.round(share * 100);
}

/**
 * Written as the verification email goes out: the account exists, where the
 * link was sent, and what verifying unlocks while the offer still stands.
 */
export function verificationSentMessage(
  role: RewardRole,
  email: string,
  reward: { studentMinutes: number; teacherShare: number; teacherBonusMinutes: number } | undefined
): InboxMessage {
  let rewardEn = "";
  let rewardHe = "";
  if (reward && role === "teacher" && reward.teacherBonusMinutes > 0) {
    const p = percent(reward.teacherShare);
    rewardEn = ` Verify it to keep ${p}% of your earnings for your first ${reward.teacherBonusMinutes} minutes of teaching.`;
    rewardHe = ` אמת/י אותו וקבל/י ${p}% מההכנסות על ${reward.teacherBonusMinutes} דקות ההוראה הראשונות שלך.`;
  } else if (reward && role === "student" && reward.studentMinutes > 0) {
    rewardEn = ` Verify it to get ${reward.studentMinutes} free minutes.`;
    rewardHe = ` אמת/י אותו וקבל/י ${reward.studentMinutes} דקות חינם.`;
  }
  return {
    title: "Your account is ready",
    text: `We sent a verification link to ${email}. Open it on this phone to verify your email address.${rewardEn}`,
    titleHe: "החשבון שלך מוכן",
    textHe: `שלחנו קישור אימות אל ${email}. פתח/י אותו בטלפון הזה כדי לאמת את כתובת המייל.${rewardHe}`,
  };
}

/** Written as the verified-email reward is granted. */
export function emailRewardMessage(
  role: RewardRole,
  reward: { studentMinutes: number; teacherShare: number; teacherBonusMinutes: number }
): InboxMessage {
  if (role === "teacher") {
    const p = percent(reward.teacherShare);
    return {
      title: "Welcome bonus unlocked",
      text: `Your email address is verified. You keep ${p}% of your earnings for your next ${reward.teacherBonusMinutes} minutes of teaching.`,
      titleHe: "בונוס ההצטרפות הופעל",
      textHe: `כתובת המייל שלך אומתה. את/ה מקבל/ת ${p}% מההכנסות על ${reward.teacherBonusMinutes} דקות ההוראה הבאות שלך.`,
    };
  }
  return {
    title: `${reward.studentMinutes} free minutes added`,
    text: `Your email address is verified, and ${reward.studentMinutes} free minutes were added to your account. Enjoy your first lessons!`,
    titleHe: `נוספו ${reward.studentMinutes} דקות חינם`,
    textHe: `כתובת המייל שלך אומתה, ו-${reward.studentMinutes} דקות חינם נוספו לחשבון שלך. תהנה/י מהשיעורים הראשונים!`,
  };
}

/** Written as a new student's sign-up minutes are granted. */
export function signupMinutesMessage(minutes: number): InboxMessage {
  return {
    title: `${minutes} free minutes added`,
    text: `Welcome! ${minutes} free minutes were added to your account for signing up.`,
    titleHe: `נוספו ${minutes} דקות חינם`,
    textHe: `ברוך/ה הבא/ה! ${minutes} דקות חינם נוספו לחשבון שלך על ההרשמה.`,
  };
}
