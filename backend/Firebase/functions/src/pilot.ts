// ─── Android pilot sign-up ───────────────────────────────────────────────────
//
// Both Android apps are in Google Play closed testing, so Play only lets an
// account download them once its address is on the testers list. The website
// (public/index.html) asks Android visitors to register first; each sign-up is
// stored in `pilotRegistrations/{app}:{email}` and the support recipients are
// told about it, so the owner can add the address to the Play Console list.
//
// Once it is added, set the document's `status` to "approved" (the admin
// dashboard's Pilot page does it, or edit it in the Firebase console) and
// `onPilotRegistrationUpdated` emails the person that they can download now.
//
// The collection is server-only: firestore.rules does not name it, so its
// catch-all denies every client read and write.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { Timestamp } from "firebase-admin/firestore";

import { sendMail } from "./mailer";
import { sendSupportEmail } from "./contactSupport";

const firestore = admin.firestore();

export const PILOT_COLLECTION = "pilotRegistrations";

export type PilotApp = "teacher" | "student";
export type PilotLang = "he" | "en";

const APP_NAMES: Record<PilotApp, { he: string; en: string }> = {
  teacher: { he: "Pro Teacher", en: "Pro Teacher" },
  student: { he: "מורה לרגע", en: "Instant Teacher" },
};

const PACKAGE_IDS: Record<PilotApp, string> = {
  teacher: "com.yaronj.tim",
  student: "com.yaronj.student",
};

// Also refuses quotes and angle brackets: the address is rendered into the
// admin dashboard's markup, and no real mailbox needs them.
const EMAIL_PATTERN = /^[^\s@/"'<>]+@[^\s@/"'<>]+\.[^\s@/"'<>]+$/;

/** Lower-cased, trimmed address, or null when it is not one. */
export function normalizePilotEmail(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const email = raw.trim().toLowerCase();
  if (email.length > 254 || !EMAIL_PATTERN.test(email)) return null;
  return email;
}

export function pilotDocId(app: PilotApp, email: string): string {
  return `${app}:${email}`;
}

export function buildApprovedEmail(
  app: PilotApp,
  lang: PilotLang
): { subject: string; text: string } {
  const pkg = PACKAGE_IDS[app];
  const storeUrl = `https://play.google.com/store/apps/details?id=${pkg}`;
  const optInUrl = `https://play.google.com/apps/testing/${pkg}`;
  const name = APP_NAMES[app][lang];

  if (lang === "he") {
    return {
      subject: `${name} מוכנה להורדה`,
      text: [
        "שלום,",
        "",
        `נוספתם לפיילוט של ${name} ל-Android, ואפשר להוריד את האפליקציה כבר עכשיו.`,
        "",
        "1. הצטרפו לבדיקה (פעם אחת), מהמכשיר ועם חשבון Google שאיתו נרשמתם:",
        optInUrl,
        "2. הורידו את האפליקציה מ-Google Play:",
        storeUrl,
        "",
        "תודה שאתם חלק מהפיילוט!",
        "צוות מורה לרגע",
      ].join("\n"),
    };
  }

  return {
    subject: `${name} is ready to download`,
    text: [
      "Hi,",
      "",
      `You've been added to the ${name} Android pilot, and you can download the app now.`,
      "",
      "1. Join the test (once), on your device and with the Google account you registered:",
      optInUrl,
      "2. Download the app from Google Play:",
      storeUrl,
      "",
      "Thanks for being part of the pilot!",
      "The Instant Teacher team",
    ].join("\n"),
  };
}

// ─── registerPilot ───────────────────────────────────────────────────────────
//
// Public: the visitor has no account yet. Registering twice is harmless — the
// existing document is left as it is and its status returned, so the page can
// tell an approved visitor to go ahead and download.

export const registerPilot = onCall(async (req) => {
  const { email: rawEmail, app, lang } = (req.data ?? {}) as Record<string, unknown>;

  if (app !== "teacher" && app !== "student") {
    throw new HttpsError("invalid-argument", "app must be teacher or student");
  }
  const email = normalizePilotEmail(rawEmail);
  if (!email) throw new HttpsError("invalid-argument", "A valid email is required");
  const language: PilotLang = lang === "en" ? "en" : "he";

  const ref = firestore.collection(PILOT_COLLECTION).doc(pilotDocId(app, email));
  const created = await firestore.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) return { created: false, status: String(existing.get("status") ?? "pending") };
    tx.create(ref, {
      email,
      app,
      lang: language,
      platform: "android",
      status: "pending",
      createdAt: Timestamp.now(),
    });
    return { created: true, status: "pending" };
  });

  if (created.created) {
    logger.info(`[pilot] new ${app} registration ${email}`);
    try {
      await sendSupportEmail(
        `[Teacher in a Minute] Android pilot sign-up: ${APP_NAMES[app].en}`,
        [
          `${email} registered for the ${APP_NAMES[app].en} Android pilot (${PACKAGE_IDS[app]}).`,
          "",
          "Add the address to the Play Console closed-testing list, then approve it",
          "on the admin dashboard's Pilot page to email them that they can download.",
        ].join("\n")
      );
    } catch (error) {
      // The registration is saved either way; the owner can still see it on
      // the dashboard.
      logger.error("[pilot] owner notification failed", error);
    }
  }

  return { status: created.status, alreadyRegistered: !created.created };
});

// ─── onPilotRegistrationUpdated ──────────────────────────────────────────────
//
// Emails the person the first time their registration turns "approved".
// `notifiedAt` records the send so re-approving does not mail them again.

export const onPilotRegistrationUpdated = onDocumentUpdated(
  `${PILOT_COLLECTION}/{registrationId}`,
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after) return;
    if (after.status !== "approved" || before.status === "approved" || after.notifiedAt) return;

    const app = after.app as PilotApp;
    if (app !== "teacher" && app !== "student") return;
    const lang: PilotLang = after.lang === "en" ? "en" : "he";

    const { subject, text } = buildApprovedEmail(app, lang);
    const sent = await sendMail({ to: String(after.email), subject, text });
    if (sent) {
      await event.data!.after.ref.update({ notifiedAt: Timestamp.now() });
      logger.info(`[pilot] told ${after.email} they can download ${app}`);
    }
  }
);
