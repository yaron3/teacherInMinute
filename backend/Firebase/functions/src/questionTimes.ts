// ─── Question times as Firestore Timestamps ──────────────────────────────────
//
// A question's live copy in RTDB holds its times as plain milliseconds. When a
// lesson ends, ./lessons copies that node back over the Firestore record, and
// used to leave the times as numbers. Firestore range queries never match
// across types, so every question that ended in a lesson dropped out of each
// "since" query on these fields: the Live page's last hour, the Overview's
// last day, the public status page.
//
// The apps, the web client and the backend all read either form, so turning
// the numbers back into Timestamps changes nothing they show.

import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

/** The fields a question record keeps as Timestamps in Firestore. */
export const QUESTION_TIME_FIELDS = ["createdAt", "acceptedAt", "startedAt", "searchEndsAt", "minutesDeadlineAt"] as const;

/** Milliseconds (or seconds, from older writers) as a Timestamp. */
function numberToTimestamp(value: number): Timestamp | null {
  if (!Number.isFinite(value) || value <= 0) return null;
  return Timestamp.fromMillis(value < 1e12 ? value * 1000 : value);
}

/**
 * The record's time fields that are plain numbers, as Timestamps — the update
 * that repairs them. Empty when there is nothing to change.
 */
export function questionTimeFixes(record: Record<string, unknown>): Record<string, Timestamp> {
  const fixes: Record<string, Timestamp> = {};
  for (const field of QUESTION_TIME_FIELDS) {
    const value = record[field];
    if (typeof value !== "number") continue;
    const ts = numberToTimestamp(value);
    if (ts) fixes[field] = ts;
  }
  return fixes;
}

/** `record` with its numeric time fields as Timestamps. */
export function withQuestionTimestamps<T extends Record<string, unknown>>(record: T): T {
  return { ...record, ...questionTimeFixes(record) };
}

/** At most this many records are repaired per call, so one call stays well
 *  inside a function's time limit; the console calls again until none are left. */
export const QUESTION_TIME_REPAIR_BATCH = 300;

/**
 * Finds question records with numeric time fields and, unless `dryRun`, turns
 * them into Timestamps. A range on a number matches numbers only, so each
 * field's query returns exactly the records that need it.
 */
export async function repairQuestionTimes(
  dryRun: boolean
): Promise<{ found: number; repaired: number; more: boolean; sample: string[] }> {
  const firestore = admin.firestore();
  const docs = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
  for (const field of QUESTION_TIME_FIELDS) {
    if (docs.size >= QUESTION_TIME_REPAIR_BATCH) break;
    const snap = await firestore
      .collection("questions")
      .where(field, ">=", 0)
      .limit(QUESTION_TIME_REPAIR_BATCH - docs.size)
      .get();
    for (const d of snap.docs) docs.set(d.id, d);
  }

  let repaired = 0;
  if (!dryRun) {
    const batchSize = 400;
    const entries = [...docs.values()];
    for (let i = 0; i < entries.length; i += batchSize) {
      const batch = firestore.batch();
      for (const d of entries.slice(i, i + batchSize)) {
        const fixes = questionTimeFixes(d.data());
        if (Object.keys(fixes).length) {
          batch.update(d.ref, fixes);
          repaired++;
        }
      }
      await batch.commit();
    }
  }
  return {
    found: docs.size,
    repaired,
    more: docs.size >= QUESTION_TIME_REPAIR_BATCH,
    sample: [...docs.keys()].slice(0, 5),
  };
}
