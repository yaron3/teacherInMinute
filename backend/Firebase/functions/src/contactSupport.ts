// ─── Contact Us → email ──────────────────────────────────────────────────────
//
// The app saves a Settings → About → Contact Us message to
// `contactRequests/{id}`. This trigger forwards each new one by email to the
// support recipients set in the admin console (see ./supportSettings). Each
// email links to the case on the hosted support page
// (`public/support.html?case=<id>`), where an admin signs in and replies.
//
// Mail goes out over SMTP, configured by env vars (see .env):
//   SMTP_HOST, SMTP_PORT (default 587), SMTP_USER, SMTP_PASS, SMTP_FROM
// Without SMTP_HOST the message is logged instead of sent, so the emulator and
// unconfigured environments do not fail. The request document stays in
// Firestore either way.

import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as nodemailer from "nodemailer";

import { readSupportSettings, supportCaseUrl } from "./supportSettings";

export { readContactRecipients, readSupportSettings, supportCaseUrl } from "./supportSettings";

/** Strips CR/LF so user text cannot inject headers into the subject. */
function oneLine(text: unknown): string {
  return String(text ?? "").replace(/[\r\n]+/g, " ").trim();
}

export function buildContactEmail(
  data: Record<string, unknown>,
  caseUrl?: string
): { subject: string; text: string } {
  const field = (key: string) => String(data[key] ?? "");
  const tag = data.sample === true ? "[TEST] " : "";
  const subject = `${tag}[Teacher in a Minute] ${oneLine(data.title) || "Contact request"}`;
  const text = [
    ...(caseUrl ? [`Open the case to reply: ${caseUrl}`, ""] : []),
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

/**
 * Sends `subject` and `text` to the support recipients. Returns false, having
 * logged it, when SMTP is not configured; throws if the send itself fails.
 * Also used for teacher reports (see moderation.ts).
 */
export async function sendSupportEmail(subject: string, text: string, replyToAddress?: unknown): Promise<boolean> {
  const { recipients } = await readSupportSettings();
  if (recipients.length === 0) {
    logger.warn(`[contactSupport] no support recipients set; not sending. subject=${subject}`);
    return false;
  }

  const host = process.env.SMTP_HOST;
  if (!host) {
    logger.warn(
      `[contactSupport] SMTP_HOST not set; not sending. to=${recipients.join(",")} subject=${subject}`
    );
    return false;
  }

  const transport = nodemailer.createTransport({
    host,
    port: Number(process.env.SMTP_PORT ?? 587),
    auth: process.env.SMTP_USER
      ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS ?? "" }
      : undefined,
  });

  const replyTo = typeof replyToAddress === "string" && replyToAddress.includes("@")
    ? replyToAddress
    : undefined;

  await transport.sendMail({
    from: process.env.SMTP_FROM ?? process.env.SMTP_USER,
    to: recipients,
    replyTo,
    subject,
    text,
  });
  logger.info(`[contactSupport] sent "${subject}" to ${recipients.length} recipient(s)`);
  return true;
}

export const onContactRequestCreated = onDocumentCreated(
  "contactRequests/{requestId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const { subject, text } = buildContactEmail(data, supportCaseUrl(event.params.requestId));
    // Throwing lets Firestore retry if retries are enabled; otherwise it is logged.
    const sent = await sendSupportEmail(subject, text, data.userEmail);
    if (sent) logger.info(`[contactSupport] sent request ${event.params.requestId}`);
  }
);
