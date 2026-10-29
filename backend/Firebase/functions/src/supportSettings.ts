// ─── Support settings ────────────────────────────────────────────────────────
//
// Who is emailed about a new support request, and where its case link points.
// Kept apart from contactSupport.ts, which registers a Firestore trigger, so the
// admin callables can use it without loading that trigger.
//
// Recipients are set in the admin console (Support page) and stored in
// `adminSettings/support`. Until the console saves a list, the recipients in
// `support-config.json` (functions root, next to package.json) are used.
//
// The case link opens the hosted support page (`public/support.html?case=<id>`)
// on SUPPORT_SITE_URL, or SUPPORT_SITE_URL_DEFAULT when that is not set.

import * as fs from "node:fs";
import * as path from "node:path";

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { Timestamp } from "firebase-admin/firestore";

import { ADMIN_SETTINGS_COLLECTION, isPlausibleEmail, parseRecipients } from "./dailyReport";

const CONFIG_PATH = path.join(__dirname, "..", "support-config.json");
const FALLBACK_RECIPIENTS = ["support@moreh-lerega.co.il"];
export const SUPPORT_SETTINGS_DOC = "support";
export const SUPPORT_SITE_URL_DEFAULT = "https://teacher-in-a-moment.web.app";

/** Recipients from support-config.json; the default if the file is missing or empty. */
export function readContactRecipients(configPath = CONFIG_PATH): string[] {
  try {
    const parsed = JSON.parse(fs.readFileSync(configPath, "utf8")) as {
      contactRecipients?: unknown;
    };
    const list = Array.isArray(parsed.contactRecipients)
      ? parsed.contactRecipients.filter(
          (value): value is string => typeof value === "string" && value.includes("@")
        )
      : [];
    return list.length > 0 ? list : FALLBACK_RECIPIENTS;
  } catch (error) {
    logger.warn(`[contactSupport] cannot read ${configPath}, using default`, error);
    return FALLBACK_RECIPIENTS;
  }
}

export interface SupportSettings {
  recipients: string[];
  /** False while the console has never saved a list and the config file's is used. */
  saved: boolean;
}

function supportSettingsRef() {
  return admin.firestore().collection(ADMIN_SETTINGS_COLLECTION).doc(SUPPORT_SETTINGS_DOC);
}

/** The recipients saved in the admin console, or the config file's until it saves any. */
export async function readSupportSettings(): Promise<SupportSettings> {
  const data = (await supportSettingsRef().get()).data() ?? {};
  if (data.recipients === undefined) return { recipients: readContactRecipients(), saved: false };
  return { recipients: parseRecipients(data.recipients).filter(isPlausibleEmail), saved: true };
}

export async function writeSupportSettings(recipients: string[], by: string | undefined): Promise<void> {
  await supportSettingsRef().set(
    { recipients, updatedAt: Timestamp.now(), updatedBy: by ?? null },
    { merge: true }
  );
}

/** Where the support page opens case `requestId`. */
export function supportCaseUrl(requestId: string, siteUrl = process.env.SUPPORT_SITE_URL || SUPPORT_SITE_URL_DEFAULT): string {
  return `${siteUrl.replace(/\/+$/, "")}/support.html?case=${encodeURIComponent(requestId)}`;
}
