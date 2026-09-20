#!/usr/bin/env node
/**
 * Grants or revokes the `admin` custom claim that gates every admin callable
 * (see src/admin.ts `assertAdmin`).
 *
 * Deliberately a local script rather than a callable: a function that can grant
 * admin is a function an attacker can try to reach. This runs with the service
 * account key, which never leaves the machine.
 *
 *   node scripts/set-admin-claim.js <email>            # grant
 *   node scripts/set-admin-claim.js <email> --revoke   # revoke
 *
 * The account must sign out and back in (or refresh its ID token) for the new
 * claim to appear — claims are baked into the token at issue time.
 */
const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");

const [, , email, flag] = process.argv;
if (!email) {
  console.error("Usage: node scripts/set-admin-claim.js <email> [--revoke]");
  process.exit(1);
}
const revoke = flag === "--revoke";

const keyFile = fs
  .readdirSync(path.join(__dirname, ".."))
  .find((f) => f.includes("firebase-adminsdk") && f.endsWith(".json"));
if (!keyFile) {
  console.error("No service account key (*firebase-adminsdk*.json) found in functions/");
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(path.join(__dirname, "..", keyFile))),
});

(async () => {
  const user = await admin.auth().getUserByEmail(email);

  if (!user.emailVerified && !revoke) {
    console.error(
      `Refusing: ${email} has an unverified email address.\n` +
        "assertAdmin requires email_verified, so the claim would have no effect."
    );
    process.exit(1);
  }

  // Merge rather than replace, so unrelated claims survive.
  const claims = { ...(user.customClaims ?? {}) };
  if (revoke) delete claims.admin;
  else claims.admin = true;

  await admin.auth().setCustomUserClaims(user.uid, claims);
  // Invalidate outstanding tokens so a revoke takes effect immediately rather
  // than whenever the current hour-long ID token happens to expire.
  if (revoke) await admin.auth().revokeRefreshTokens(user.uid);

  console.log(
    `${revoke ? "Revoked" : "Granted"} admin for ${email} (uid=${user.uid}).\n` +
      "Sign out and back in for the change to reach the token."
  );
  process.exit(0);
})().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
