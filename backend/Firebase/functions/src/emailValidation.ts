// ─── Email validation ────────────────────────────────────────────────────────
//
// Shared by anywhere an address is typed in — teacher payout emails today,
// email signup next — so one definition of "usable address" serves both.
//
// Three levels of confidence, and it is worth being precise about which one
// each check gives:
//
//   1. Syntax      — the address is shaped like an address.
//   2. Deliverable — the domain actually accepts mail (it publishes MX, or
//                    resolves to a host that implicitly accepts it).
//   3. Exists      — that specific mailbox is real.
//
// We can do 1 and 2 here. We cannot do 3: proving a mailbox exists means an
// SMTP conversation on port 25, and Google Cloud blocks outbound port 25 from
// Cloud Functions and does not allow it to be unblocked with firewall rules.
// Even where it is reachable, most large providers (Gmail, Outlook) and any
// catch-all domain accept every recipient, so the answer would be unreliable.
//
// `EMAIL_VERIFY_API_URL` / `EMAIL_VERIFY_API_KEY` leave a seam for a
// third-party verifier (ZeroBounce, Kickbox, NeverBounce…) to supply level 3
// later. Unset — the default — level 3 is simply reported as not checked,
// never as a failure.

import { promises as dns } from "node:dns";
import { onCall } from "firebase-functions/v2/https";

export type EmailRejectionReason = "syntax" | "no_mail_domain";

export interface EmailValidationResult {
  /** Trimmed and lowercased, safe to store and compare against. */
  email: string;
  /** True when nothing we can check says the address is unusable. */
  valid: boolean;
  reason?: EmailRejectionReason;
  /** The domain publishes MX records, or resolves to an implicit mail host. */
  domainAcceptsMail: boolean;
  /** Whether mailbox existence was actually tested — false unless a
   *  third-party verifier is configured, so callers never mistake "not
   *  checked" for "exists". */
  mailboxChecked: boolean;
  /** Only meaningful when `mailboxChecked` is true. */
  mailboxExists?: boolean;
}

/** Trimmed and lowercased. Addresses are compared and stored in this form so a
 *  teacher typing "Name@Example.com" matches the sign-in address they hold. */
export function normalizeEmail(raw: unknown): string {
  return typeof raw === "string" ? raw.trim().toLowerCase() : "";
}

/** Deliberately not RFC 5322 — that grammar accepts addresses no mail provider
 *  would issue, and rejecting a real address is worse than accepting an odd
 *  one, since the domain check and the eventual send both still apply. */
export function isValidEmailSyntax(email: string): boolean {
  if (email.length < 3 || email.length > 254) return false;
  if (/\s/.test(email)) return false;

  const at = email.lastIndexOf("@");
  if (at <= 0 || at === email.length - 1) return false;

  const local = email.slice(0, at);
  const domain = email.slice(at + 1);

  if (local.length > 64) return false;
  if (local.startsWith(".") || local.endsWith(".") || local.includes("..")) return false;
  // Dot-atom characters only. Notably excludes a second "@", which splitting on
  // the last one would otherwise hide inside the local part.
  if (!/^[a-z0-9!#$%&'*+/=?^_`{|}~.-]+$/i.test(local)) return false;

  if (domain.length > 253) return false;
  if (!domain.includes(".")) return false;
  if (domain.startsWith("-") || domain.endsWith("-")) return false;
  if (domain.startsWith(".") || domain.endsWith(".") || domain.includes("..")) return false;

  // Labels: letters, digits and hyphens, not starting or ending with a hyphen.
  return domain
    .split(".")
    .every((label) => /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/i.test(label));
}

export function domainOf(email: string): string {
  return email.slice(email.lastIndexOf("@") + 1);
}

/** Whether the domain can receive mail at all: an MX record, or — per RFC 5321
 *  — an A/AAAA record, which mail servers treat as an implicit MX. A domain
 *  with neither can never receive a payout notification or a signup link. */
export async function domainAcceptsMail(domain: string): Promise<boolean> {
  try {
    const mx = await dns.resolveMx(domain);
    // A single "." host is the RFC 7505 "null MX": explicitly accepts no mail.
    const usable = mx.filter((record) => record.exchange && record.exchange !== ".");
    if (usable.length > 0) return true;
    if (mx.length > 0) return false;
  } catch {
    // No MX, or the lookup failed — fall through to the implicit-MX check.
  }

  for (const lookup of [dns.resolve4, dns.resolve6]) {
    try {
      const records = await lookup(domain);
      if (records.length > 0) return true;
    } catch {
      // Try the next record type.
    }
  }

  return false;
}

/** Optional third-party mailbox check. Returns undefined when no verifier is
 *  configured or the call fails — an outage must not block a real address. */
async function checkMailboxExists(email: string): Promise<boolean | undefined> {
  const url = process.env.EMAIL_VERIFY_API_URL;
  const key = process.env.EMAIL_VERIFY_API_KEY;
  if (!url || !key) return undefined;

  try {
    const response = await fetch(
      `${url}${url.includes("?") ? "&" : "?"}email=${encodeURIComponent(email)}`,
      { headers: { Authorization: `Bearer ${key}` } }
    );
    if (!response.ok) return undefined;
    const body = (await response.json()) as { deliverable?: boolean; result?: string };
    if (typeof body.deliverable === "boolean") return body.deliverable;
    if (typeof body.result === "string") return body.result === "deliverable";
    return undefined;
  } catch {
    return undefined;
  }
}

export async function validateEmail(raw: unknown): Promise<EmailValidationResult> {
  const email = normalizeEmail(raw);

  if (!isValidEmailSyntax(email)) {
    return { email, valid: false, reason: "syntax", domainAcceptsMail: false, mailboxChecked: false };
  }

  const acceptsMail = await domainAcceptsMail(domainOf(email));
  if (!acceptsMail) {
    return { email, valid: false, reason: "no_mail_domain", domainAcceptsMail: false, mailboxChecked: false };
  }

  const exists = await checkMailboxExists(email);
  return {
    email,
    valid: exists === false ? false : true,
    domainAcceptsMail: true,
    mailboxChecked: exists !== undefined,
    ...(exists !== undefined ? { mailboxExists: exists } : {}),
  };
}

/** Checks an address without storing anything, so any screen that takes one —
 *  email signup, the teacher payout form — can tell the user it is wrong while
 *  they are still looking at the field, instead of failing later.
 *
 *  Callable without being signed in: signup needs it before an account exists.
 *  It only reads public DNS, so it discloses nothing about our users. */
export const validateEmailAddress = onCall(async (req) => {
  const raw = (req.data as Record<string, unknown>)?.email;
  const result = await validateEmail(raw);
  return {
    email: result.email,
    valid: result.valid,
    reason: result.reason ?? null,
    domainAcceptsMail: result.domainAcceptsMail,
    mailboxChecked: result.mailboxChecked,
    mailboxExists: result.mailboxExists ?? null,
    message: result.valid ? null : emailRejectionMessage(result),
  };
});

/** A human-readable reason, for showing to whoever typed the address. */
export function emailRejectionMessage(result: EmailValidationResult): string {
  switch (result.reason) {
    case "syntax":
      return "Enter a valid email address.";
    case "no_mail_domain":
      return `${domainOf(result.email) || "That domain"} does not accept email. Check the spelling.`;
    default:
      return result.mailboxChecked && result.mailboxExists === false
        ? "That email address does not exist."
        : "Enter a valid email address.";
  }
}
