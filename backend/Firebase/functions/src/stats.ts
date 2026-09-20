// ─── Platform statistics ─────────────────────────────────────────────────────
//
// Aggregate, non-identifying counters the apps show on the student home screen
// ("N sec avg to connect"). They live in a single Firestore document that any
// signed-in user may read and only this backend may write (see
// firestore.rules → `stats/{docId}`), so the client pays one document read
// rather than scanning the questions collection.
//
// Running totals are kept alongside the derived average so a new sample is an
// O(1) update and readers never have to divide.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { Timestamp } from "firebase-admin/firestore";

const firestore = admin.firestore();

export const STATS_COLLECTION = "stats";
export const PLATFORM_STATS_DOC = "platform";

/** Samples longer than this are questions that sat unanswered and were picked
 *  up much later; averaging them in would describe a queue, not a connect time. */
const MAX_CONNECT_SAMPLE_SECONDS = 15 * 60;

export interface PlatformStatsDoc {
  /** Questions a teacher accepted — the sample size behind the average. */
  connectedQuestionCount: number;
  /** Summed seconds from question created to teacher accepted. */
  totalConnectSeconds: number;
  /** Derived from the two totals above, so readers don't divide by zero. */
  averageConnectSeconds: number;
  /** Users whose role is "teacher". Shown on the student home as
   *  "N registered teachers"; maintained by `recomputeRegisteredTeacherCount`. */
  registeredTeacherCount: number;
  updatedAt: Timestamp;
}

/**
 * Recounts teacher-role users and stores the result.
 *
 * Uses Firestore's server-side `count()` aggregation, so the cost is a single
 * aggregation query rather than reading every user document. Recomputing from
 * scratch (rather than incrementing on each role change) keeps this correct
 * regardless of how a role was set — the app writes roles from several places,
 * and a missed increment would silently drift forever.
 *
 * Best-effort: callers should not fail their own work if this rejects.
 */
export async function recomputeRegisteredTeacherCount(): Promise<number> {
  const snapshot = await firestore
    .collection("users")
    .where("role", "==", "teacher")
    .count()
    .get();

  const count = numberOrZero(snapshot.data().count);

  await firestore
    .collection(STATS_COLLECTION)
    .doc(PLATFORM_STATS_DOC)
    .set({ registeredTeacherCount: count, updatedAt: Timestamp.now() }, { merge: true });

  logger.info(`[stats] registeredTeacherCount=${count}`);
  return count;
}

/**
 * Folds one connect time into the platform average.
 *
 * Deliberately best-effort: a failure here must never fail the accept that
 * produced it, so the caller is expected to ignore rejections.
 */
export async function recordQuestionConnected(
  questionId: string,
  createdAtMillis: number | undefined,
  acceptedAtMillis: number
): Promise<void> {
  if (createdAtMillis === undefined || !Number.isFinite(createdAtMillis)) {
    logger.info(`[stats] skip connect sample qid=${questionId} reason=no-createdAt`);
    return;
  }

  const seconds = (acceptedAtMillis - createdAtMillis) / 1000;
  if (!Number.isFinite(seconds) || seconds < 0 || seconds > MAX_CONNECT_SAMPLE_SECONDS) {
    logger.info(`[stats] skip connect sample qid=${questionId} seconds=${seconds} reason=out-of-range`);
    return;
  }

  const ref = firestore.collection(STATS_COLLECTION).doc(PLATFORM_STATS_DOC);

  await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const current = (snap.data() ?? {}) as Partial<PlatformStatsDoc>;

    const count = numberOrZero(current.connectedQuestionCount) + 1;
    const total = numberOrZero(current.totalConnectSeconds) + seconds;

    tx.set(
      ref,
      {
        connectedQuestionCount: count,
        totalConnectSeconds: total,
        averageConnectSeconds: Math.round(total / count),
        updatedAt: Timestamp.now(),
      },
      { merge: true }
    );
  });

  logger.info(`[stats] recorded connect sample qid=${questionId} seconds=${Math.round(seconds)}`);
}

function numberOrZero(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

// ─── Keeping registeredTeacherCount fresh ────────────────────────────────────

/**
 * Recounts teachers whenever a user document's `role` changes.
 *
 * A trigger rather than an increment at each place that writes a role: the app
 * sets roles from onboarding, the profile screen and the admin tools, and any
 * path that forgot to increment would leave the counter permanently wrong.
 *
 * The role-unchanged early return matters — user documents are written on every
 * purchase and lesson, and only a genuine role change should cost an
 * aggregation query.
 */
export const onUserRoleChange = onDocumentWritten("users/{uid}", async (event) => {
  const before = event.data?.before?.data()?.role;
  const after = event.data?.after?.data()?.role;
  if (before === after) return;
  if (before !== "teacher" && after !== "teacher") return;

  try {
    await recomputeRegisteredTeacherCount();
  } catch (err) {
    // Never fail the write that triggered this; the next role change (or an
    // admin recompute) will correct the count.
    logger.error("[stats] registeredTeacherCount recompute failed", err);
  }
});
