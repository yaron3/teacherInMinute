// ─── Demo users ──────────────────────────────────────────────────────────────
//
// Accounts used for screenshots, demos and testing are marked from the admin
// console with `users/{uid}.isDemoUser = true`, and every statistic leaves them
// out: the admin dashboard, the platform averages the apps show, and the
// online-teacher history. They still work as ordinary accounts in the app.
//
// Unrelated to `isDemo` on a question, which marks a question the demo-student
// service simulated (see ./demoStudent).
//
// Only the backend writes the flag: firestore.rules lists it among the
// server-owned user fields.

import * as admin from "firebase-admin";

export const DEMO_USER_FIELD = "isDemoUser";

/** `in` filters take at most 30 values. */
const IN_LIMIT = 30;

/** Every user marked as a demo user. */
export async function readDemoUserUids(): Promise<Set<string>> {
  const snap = await admin.firestore().collection("users").where(DEMO_USER_FIELD, "==", true).get();
  return new Set(snap.docs.map((d) => d.id));
}

/** True when any of `uids` is a demo user. Missing and empty uids are skipped. */
export async function includesDemoUser(uids: Array<string | null | undefined>): Promise<boolean> {
  const firestore = admin.firestore();
  const ids = [...new Set(uids.filter((u): u is string => typeof u === "string" && u.length > 0))];
  if (ids.length === 0) return false;
  const snaps = await firestore.getAll(...ids.map((uid) => firestore.collection("users").doc(uid)));
  return snaps.some((s) => s.data()?.[DEMO_USER_FIELD] === true);
}

/** Splits `values` into chunks an `in` filter accepts. */
export function inChunks<T>(values: T[]): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < values.length; i += IN_LIMIT) chunks.push(values.slice(i, i + IN_LIMIT));
  return chunks;
}
