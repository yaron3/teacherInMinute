// ─── Contact Us → email ──────────────────────────────────────────────────────
//
// The app saves a Settings → About → Contact Us message to
// `contactRequests/{id}`. This trigger forwards each new one by email to the
// recipients listed in `support-config.json` (functions root, next to
// package.json). Edit that file and redeploy to change who is notified.
//
// Mail goes out over SMTP, configured by env vars (see .env):
//   SMTP_HOST, SMTP_PORT (default 587), SMTP_USER, SMTP_PASS, SMTP_FROM
// Without SMTP_HOST the message is logged instead of sent, so the emulator and
// unconfigured environments do not fail. The request document stays in
// Firestore either way.

import * as fs from "node:fs";
import * as path from "node:path";

import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as nodemailer from "nodemailer";

const CONFIG_PATH = path.join(__dirname, "..", "support-config.json");
const FALLBACK_RECIPIENTS = ["yaron@yaronj.com"];

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

/** Strips CR/LF so user text cannot inject headers into the subject. */
function oneLine(text: unknown): string {
  return String(text ?? "").replace(/[\r\n]+/g, " ").trim();
}

export function buildContactEmail(data: Record<string, unknown>): { subject: string; text: string } {
  const field = (key: string) => String(data[key] ?? "");
  const subject = `[Teacher in a Minute] ${oneLine(data.title) || "Contact request"}`;
  const text = [
    field("description"),
    "",
    "—",
    `From: ${field("userName")} <${field("userEmail")}>`,
    `Role: ${field("role")}`,
    `User ID: ${field("userId")}`,
    `Sent: ${field("sentAt")}`,
    `Device: ${field("deviceType")} (${field("osVersion")})`,
    `Locale: ${field("locale")}`,
    `Request ID: ${field("id")}`,
  ].join("\n");
  return { subject, text };
}

export const onContactRequestCreated = onDocumentCreated(
  "contactRequests/{requestId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const recipients = readContactRecipients();
    const { subject, text } = buildContactEmail(data);

    const host = process.env.SMTP_HOST;
    if (!host) {
      logger.warn(
        `[contactSupport] SMTP_HOST not set; not sending. to=${recipients.join(",")} subject=${subject}`
      );
      return;
    }

    const transport = nodemailer.createTransport({
      host,
      port: Number(process.env.SMTP_PORT ?? 587),
      auth: process.env.SMTP_USER
        ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS ?? "" }
        : undefined,
    });

    const replyTo = typeof data.userEmail === "string" && data.userEmail.includes("@")
      ? data.userEmail
      : undefined;

    // Throwing lets Firestore retry if retries are enabled; otherwise it is logged.
    await transport.sendMail({
      from: process.env.SMTP_FROM ?? process.env.SMTP_USER,
      to: recipients,
      replyTo,
      subject,
      text,
    });
    logger.info(`[contactSupport] sent request ${event.params.requestId} to ${recipients.length} recipient(s)`);
  }
);
