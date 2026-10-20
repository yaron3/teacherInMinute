// ─── Outgoing mail ───────────────────────────────────────────────────────────
//
// SMTP, configured by env vars (see .env):
//   SMTP_HOST, SMTP_PORT (default 587), SMTP_USER, SMTP_PASS, SMTP_FROM
// Without SMTP_HOST a message is logged instead of sent, so the emulator and an
// unconfigured project still run.
//
// Replies to support tickets go out through their own account so they come
// from the support address: SUPPORT_SMTP_HOST, SUPPORT_SMTP_PORT,
// SUPPORT_SMTP_USER, SUPPORT_SMTP_PASS, SUPPORT_SMTP_FROM.

import * as nodemailer from "nodemailer";
import { logger } from "firebase-functions";

export interface OutgoingMail {
  to: string | string[];
  subject: string;
  text: string;
  html?: string;
  replyTo?: string;
}

export interface SmtpConfig {
  host: string | undefined;
  port: number;
  user: string | undefined;
  pass: string | undefined;
  from: string | undefined;
}

/** Env vars `${prefix}HOST`, `${prefix}PORT`, … */
function smtpConfigFromEnv(prefix: string): SmtpConfig {
  const env = (key: string) => process.env[`${prefix}${key}`] || undefined;
  const user = env("USER");
  return {
    host: env("HOST"),
    port: Number(env("PORT") ?? 587),
    user,
    pass: env("PASS"),
    from: env("FROM") ?? user,
  };
}

export const defaultSmtpConfig = () => smtpConfigFromEnv("SMTP_");
export const supportSmtpConfig = () => smtpConfigFromEnv("SUPPORT_SMTP_");

/**
 * Sends `mail`, or logs it when SMTP is not configured. Says which. Resolves
 * to the server's message ID when sent.
 */
export async function sendMail(
  mail: OutgoingMail,
  config: SmtpConfig = defaultSmtpConfig()
): Promise<string | false> {
  if (!config.host) {
    logger.warn(`[mailer] SMTP host not set; not sending. subject=${mail.subject}`);
    return false;
  }

  const transport = nodemailer.createTransport({
    host: config.host,
    port: config.port,
    auth: config.user ? { user: config.user, pass: config.pass ?? "" } : undefined,
  });

  const info = await transport.sendMail({ from: config.from, ...mail });
  return String(info?.messageId ?? "") || "sent";
}
