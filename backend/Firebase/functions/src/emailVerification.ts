// ─── Email verification by link back into the app ────────────────────────────
//
// The app asks `sendVerificationEmail` for a link; we email it ourselves
// (./mailer) rather than through Firebase's template, because Firebase's link
// ends on its own web page. Ours ends in the app:
//
//   1. The link opens `verifyEmailLink` with a one-off token.
//   2. That marks the address verified on the auth record — and, when the
//      student changed their address on the profile step, moves the account
//      onto the new one — then claims the welcome reward (./emailRewards).
//   3. It answers with a page that opens `<app scheme>://email-verified` with
//      the outcome, so the app can say whether minutes were added or the
//      promotion has ended. The page says the same, for a phone without the
//      app or a link opened on a computer.
//
// Tokens live in `emailVerificationLinks/{sha256(token)}` — hashed, so the
// collection cannot be replayed from a read — and sends are throttled per user
// in `emailVerificationSends/{uid}`. Both are server-only: the catch-all in
// firestore.rules denies them to clients.

import { createHash, randomBytes } from "node:crypto";

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { Timestamp } from "firebase-admin/firestore";

import { isValidEmailSyntax, normalizeEmail } from "./emailValidation";
import { claimEmailRewardFor, ClaimResponse, RewardRole } from "./emailRewards";
import { sendMail } from "./mailer";

const firestore = admin.firestore();

export const EMAIL_VERIFICATION_LINKS_COLLECTION = "emailVerificationLinks";
export const EMAIL_VERIFICATION_SENDS_COLLECTION = "emailVerificationSends";

const LINK_LIFETIME_MS = 24 * 3_600_000;
const MIN_SEND_INTERVAL_MS = 30_000;
const MAX_SENDS_PER_HOUR = 5;
const HOUR_MS = 3_600_000;

/** The custom scheme each app registers (Info.plist, AndroidManifest.xml). */
const APP_SCHEMES: Record<RewardRole, string> = {
  student: "teacherminute",
  teacher: "proteacher",
};

export type Language = "en" | "he";

/** What the link did, as the app and the landing page are told. */
export type LinkStatus =
  | "granted"
  | "promotion_ended"
  | "already_granted"
  | "claimed_by_other_account"
  | "verified"
  | "email_in_use"
  | "expired"
  | "invalid"
  | "error";

export function tokenId(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

function functionsBaseUrl(): string {
  return (
    process.env.PUBLIC_BASE_URL ??
    `https://us-central1-${process.env.GCLOUD_PROJECT ?? "teacher-in-a-moment"}.cloudfunctions.net`
  );
}

function languageOf(raw: unknown): Language {
  return raw === "he" ? "he" : "en";
}

function roleOf(raw: unknown): RewardRole {
  return raw === "teacher" ? "teacher" : "student";
}

/** Send timestamps still inside the hour, and whether one more is allowed. */
export function throttleSends(raw: unknown, now: number): { allowed: boolean; kept: number[] } {
  const kept = (Array.isArray(raw) ? raw : [])
    .map((value) => Number(value))
    .filter((value) => Number.isFinite(value) && value > now - HOUR_MS && value <= now)
    .sort((a, b) => a - b);
  const last = kept[kept.length - 1];
  const allowed =
    kept.length < MAX_SENDS_PER_HOUR && (last === undefined || now - last >= MIN_SEND_INTERVAL_MS);
  return { allowed, kept };
}

/** What the reward claim means for the person who just opened the link. */
export function linkStatusForClaim(claim: ClaimResponse): LinkStatus {
  switch (claim.status) {
    case "granted":
    case "promotion_ended":
    case "already_granted":
    case "claimed_by_other_account":
      return claim.status;
    default:
      return "verified";
  }
}

/** The URL the landing page opens in the app. */
export function appDeepLink(role: RewardRole, status: LinkStatus, claim?: ClaimResponse): string {
  const params = new URLSearchParams({ status });
  if (claim && status === "granted") {
    if (claim.role === "teacher") {
      params.set("percent", String(Math.round(claim.teacherShare * 100)));
      params.set("bonusMinutes", String(claim.teacherBonusMinutesRemaining));
    } else {
      params.set("minutes", String(claim.minutesAdded ?? claim.studentMinutes));
    }
  }
  return `${APP_SCHEMES[role]}://email-verified?${params.toString()}`;
}

// ─── Copy ────────────────────────────────────────────────────────────────────

function appName(role: RewardRole, language: Language): string {
  if (role === "teacher") return "Pro Teacher";
  return language === "he" ? "מורה לרגע" : "Instant Teacher";
}

export function buildVerificationEmail(
  link: string,
  role: RewardRole,
  language: Language
): { subject: string; text: string; html: string } {
  const name = appName(role, language);
  const he = language === "he";
  const subject = he ? `אימות כתובת המייל שלך ב${name}` : `Verify your email for ${name}`;
  const intro = he
    ? "כדי לאמת את כתובת המייל שלך, הקש על הכפתור. הקישור יפתח את האפליקציה."
    : "Tap the button to verify your email address. The link opens the app.";
  const button = he ? "אימות המייל" : "Verify email";
  const ignore = he
    ? "אם לא ביקשת את זה, אפשר להתעלם מהמייל. הקישור תקף ל-24 שעות."
    : "If you didn't ask for this, you can ignore this email. The link works for 24 hours.";
  const dir = he ? "rtl" : "ltr";

  const text = `${intro}\n\n${link}\n\n${ignore}\n`;
  const html = `<!doctype html><html dir="${dir}"><body style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#1b1b2f;padding:24px">
<h2 style="margin:0 0 12px">${name}</h2>
<p style="font-size:16px;line-height:1.5">${intro}</p>
<p style="margin:28px 0"><a href="${link}" style="background:#3fe0f2;color:#0b0b1a;text-decoration:none;font-weight:700;padding:14px 28px;border-radius:8px;display:inline-block">${button}</a></p>
<p style="font-size:13px;color:#666">${ignore}</p>
</body></html>`;
  return { subject, text, html };
}

const PAGE_COPY: Record<LinkStatus, Record<Language, [string, string]>> = {
  granted: {
    en: ["Email verified", "Your free minutes were added. Open the app to start learning."],
    he: ["המייל אומת", "הדקות החינמיות נוספו לחשבון שלך. פתח את האפליקציה כדי להתחיל ללמוד."],
  },
  promotion_ended: {
    en: ["Email verified", "Thanks for verifying your email. The free-minutes promotion has ended."],
    he: ["המייל אומת", "תודה שאימתת את המייל. מבצע הדקות החינמיות הסתיים."],
  },
  already_granted: {
    en: ["Email verified", "Your welcome reward was already added to your account."],
    he: ["המייל אומת", "מתנת ההצטרפות כבר נוספה לחשבון שלך."],
  },
  claimed_by_other_account: {
    en: ["Email verified", "This email address has already received its welcome reward."],
    he: ["המייל אומת", "כתובת המייל הזו כבר קיבלה את מתנת ההצטרפות."],
  },
  verified: {
    en: ["Email verified", "Thanks for verifying your email."],
    he: ["המייל אומת", "תודה שאימתת את המייל."],
  },
  email_in_use: {
    en: ["Email address in use", "Another account already uses this email address."],
    he: ["כתובת המייל בשימוש", "חשבון אחר כבר משתמש בכתובת המייל הזו."],
  },
  expired: {
    en: ["Link expired", "This verification link has expired. Ask for a new one in the app."],
    he: ["פג תוקף הקישור", "פג תוקפו של קישור האימות. אפשר לבקש קישור חדש באפליקציה."],
  },
  invalid: {
    en: ["Link not valid", "This verification link is not valid. Ask for a new one in the app."],
    he: ["הקישור אינו תקף", "קישור האימות אינו תקף. אפשר לבקש קישור חדש באפליקציה."],
  },
  error: {
    en: ["Couldn't verify your email", "Something went wrong. Please try again later."],
    he: ["לא הצלחנו לאמת את המייל", "משהו השתבש. נסה שוב מאוחר יותר."],
  },
};

export function buildLandingPage(status: LinkStatus, deepLink: string, language: Language): string {
  const [title, message] = PAGE_COPY[status][language];
  const button = language === "he" ? "פתיחת האפליקציה" : "Open the app";
  const dir = language === "he" ? "rtl" : "ltr";
  return `<!doctype html><html dir="${dir}" lang="${language}"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title}</title>
<style>body{margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#14142b;color:#fff;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;text-align:center;padding:24px;box-sizing:border-box}
a{display:inline-block;margin-top:24px;background:#3fe0f2;color:#0b0b1a;text-decoration:none;font-weight:700;padding:14px 28px;border-radius:8px}
p{color:#c9c9e0;font-size:17px;line-height:1.5;max-width:420px}</style>
</head><body><main><h1>${title}</h1><p>${message}</p><a href="${deepLink}">${button}</a></main>
<script>window.location.href=${JSON.stringify(deepLink)};</script>
</body></html>`;
}

// ─── sendVerificationEmail (callable) ────────────────────────────────────────

/**
 * Emails the caller a verification link.
 *
 * `email` is optional: without it the link verifies the account's own address;
 * with a different one it moves the account onto that address once followed,
 * already verified. `language` ("en" | "he") picks the copy.
 */
export const sendVerificationEmail = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");
  const data = (req.data ?? {}) as Record<string, unknown>;

  const authUser = await admin.auth().getUser(uid);
  const current = normalizeEmail(authUser.email);
  if (!current) throw new HttpsError("failed-precondition", "This account has no email address");

  const target = data.email === undefined || data.email === null ? current : normalizeEmail(data.email);
  if (!isValidEmailSyntax(target)) throw new HttpsError("invalid-argument", "Enter a valid email address");

  if (target !== current) {
    try {
      const other = await admin.auth().getUserByEmail(target);
      if (other.uid !== uid) throw new HttpsError("already-exists", "This email address is already in use");
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      if ((err as { code?: string }).code !== "auth/user-not-found") throw err;
    }
  } else if (authUser.emailVerified) {
    return { status: "already_verified" };
  }

  const now = Date.now();
  const sendsRef = firestore.collection(EMAIL_VERIFICATION_SENDS_COLLECTION).doc(uid);
  const throttle = throttleSends((await sendsRef.get()).data()?.sentAt, now);
  if (!throttle.allowed) {
    throw new HttpsError("resource-exhausted", "Too many verification emails. Try again later.");
  }

  // The app says which one it is: a brand-new account has no saved role yet.
  const role =
    data.app === "student" || data.app === "teacher"
      ? data.app
      : roleOf((await firestore.collection("users").doc(uid).get()).data()?.role);
  const language = languageOf(data.language);

  const token = randomBytes(32).toString("base64url");
  await firestore.collection(EMAIL_VERIFICATION_LINKS_COLLECTION).doc(tokenId(token)).set({
    uid,
    email: target,
    role,
    language,
    createdAt: Timestamp.fromMillis(now),
    expiresAt: Timestamp.fromMillis(now + LINK_LIFETIME_MS),
  });
  await sendsRef.set({ sentAt: [...throttle.kept, now] });

  const link = `${functionsBaseUrl()}/verifyEmailLink?t=${encodeURIComponent(token)}`;
  const sent = await sendMail({ to: target, ...buildVerificationEmail(link, role, language) });
  if (!sent) throw new HttpsError("unavailable", "Email is not configured");

  logger.info(`[emailVerification] sent uid=${uid} change=${target !== current}`);
  return { status: "sent" };
});

// ─── verifyEmailLink (HTTP) ──────────────────────────────────────────────────

export const verifyEmailLink = onRequest(async (req, res) => {
  const token = typeof req.query.t === "string" ? req.query.t : "";
  const ref = token ? firestore.collection(EMAIL_VERIFICATION_LINKS_COLLECTION).doc(tokenId(token)) : null;
  const link = ref ? (await ref.get()).data() : undefined;

  const role = roleOf(link?.role);
  const language = languageOf(link?.language ?? (req.acceptsLanguages("he") ? "he" : "en"));
  const answer = (status: LinkStatus, claim?: ClaimResponse) => {
    res.set("Cache-Control", "no-store");
    res.status(200).send(buildLandingPage(status, appDeepLink(role, status, claim), language));
  };

  if (!ref || !link) {
    answer("invalid");
    return;
  }
  const expiresAt = link.expiresAt as Timestamp | undefined;
  if (!expiresAt || expiresAt.toMillis() < Date.now()) {
    answer("expired");
    return;
  }

  const uid = String(link.uid);
  const email = normalizeEmail(link.email);
  try {
    const user = await admin.auth().getUser(uid);
    if (normalizeEmail(user.email) !== email) {
      await admin.auth().updateUser(uid, { email, emailVerified: true });
      // The profile keeps a copy of the address; keep it the one they use.
      await firestore.collection("users").doc(uid).set({ email }, { merge: true });
    } else if (!user.emailVerified) {
      await admin.auth().updateUser(uid, { emailVerified: true });
    }
  } catch (err) {
    const code = (err as { code?: string }).code;
    logger.warn(`[emailVerification] apply failed uid=${uid} code=${code}`);
    if (code === "auth/email-already-exists") answer("email_in_use");
    else if (code === "auth/user-not-found") answer("invalid");
    else answer("error");
    return;
  }
  await ref.set({ usedAt: Timestamp.now() }, { merge: true });

  try {
    const claim = await claimEmailRewardFor(uid);
    const status = linkStatusForClaim(claim);
    logger.info(`[emailVerification] verified uid=${uid} reward=${claim.status}`);
    answer(status, claim);
  } catch (err) {
    // The address is verified either way; the app's next check claims it.
    logger.error(`[emailVerification] claim failed uid=${uid}`, err);
    answer("verified");
  }
});
