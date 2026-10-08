// ─── Outgoing mail ───────────────────────────────────────────────────────────
//
// SMTP, configured by env vars (see .env):
//   SMTP_HOST, SMTP_PORT (default 587), SMTP_USER, SMTP_PASS, SMTP_FROM
// Without SMTP_HOST a message is logged instead of sent, so the emulator and an
// unconfigured project still run.

import * as nodemailer from "nodemailer";
import { logger } from "firebase-functions";

export interface OutgoingMail {
  to: string | string[];
  subject: string;
  text: string;
  html?: string;
  replyTo?: string;
}

/** Sends `mail`, or logs it when SMTP is not configured. Says which. */
export async function sendMail(mail: OutgoingMail): Promise<boolean> {
  const host = process.env.SMTP_HOST;
  if (!host) {
    logger.warn(`[mailer] SMTP_HOST not set; not sending. subject=${mail.subject}`);
    return false;
  }

  const transport = nodemailer.createTransport({
    host,
    port: Number(process.env.SMTP_PORT ?? 587),
    auth: process.env.SMTP_USER
      ? { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS ?? "" }
      : undefined,
  });

  await transport.sendMail({
    from: process.env.SMTP_FROM ?? process.env.SMTP_USER,
    ...mail,
  });
  return true;
}
