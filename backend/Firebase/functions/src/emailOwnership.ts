// ─── Proof that a user controls an email address ─────────────────────────────
//
// Separate from ./emailValidation, which only asks whether an address could
// receive mail at all. This asks the different question: do we already know
// *this* user reads it?
//
// We do, without asking them to prove anything again, when the address is one
// an identity provider already vouched for:
//
//   • Google, Apple, Facebook and any future federated provider — signing in
//     through them is itself proof they hold that mailbox.
//   • An email/password account whose address Firebase has marked verified,
//     because that only happens after the user follows a link sent to it.
//
// Anything else — a different address from the one they signed in with, or an
// email/password account that never confirmed its address — is unproven, and
// the caller must verify ownership before treating it as trusted.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import { normalizeEmail } from "./emailValidation";

/** Firebase's provider id for email/password accounts, which vouch for nothing
 *  on their own — `emailVerified` is what carries the proof there. */
const PASSWORD_PROVIDER = "password";

/** Every address this user has already proven they control, normalized. */
export async function provenEmails(uid: string): Promise<Set<string>> {
  const proven = new Set<string>();

  let user: admin.auth.UserRecord;
  try {
    user = await admin.auth().getUser(uid);
  } catch (err) {
    // Treat an unreadable auth record as "nothing proven" rather than failing
    // the caller: the worst outcome is asking for a verification we did not
    // strictly need.
    logger.warn(`[emailOwnership] could not read auth record uid=${uid}`, err);
    return proven;
  }

  if (user.emailVerified && user.email) {
    proven.add(normalizeEmail(user.email));
  }

  for (const provider of user.providerData ?? []) {
    if (provider.providerId === PASSWORD_PROVIDER) continue;
    if (provider.email) proven.add(normalizeEmail(provider.email));
  }

  return proven;
}

/** True when the user must still prove they control `email`. */
export async function requiresOwnershipVerification(
  uid: string,
  email: string
): Promise<boolean> {
  const proven = await provenEmails(uid);
  return !proven.has(normalizeEmail(email));
}
