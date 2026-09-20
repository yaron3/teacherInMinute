// ─── Teacher rating aggregates ───────────────────────────────────────────────
//
// A teacher's star average and review count, read by:
//   • the teacher's own dashboard and profile,
//   • a student waiting to be connected to that teacher.
//
// It needs a callable because `teachers/{uid}` is readable only by that teacher
// (firestore.rules) — students must not be able to page through teacher
// records. This function returns nothing but the two aggregate numbers, for
// teachers the caller names explicitly.
//
// `rateTeacher` (./lessons.ts) maintains `averageRate` and `ratingCount` on the
// teacher document, so the common path here is one document read per teacher.
// Teachers rated before `ratingCount` existed are backfilled on first read.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";

const firestore = admin.firestore();

/** Bounds the fan-out of a single call; screens ask for one or a handful. */
const MAX_TEACHERS_PER_CALL = 25;

export interface TeacherRatingAggregate {
  teacherId: string;
  /** Mean of every rating received, 0 when the teacher has none yet. */
  averageRating: number;
  ratingCount: number;
}

/** Reads one teacher's aggregate, counting the `ratings` subcollection only
 *  when the denormalised count is missing (pre-existing teachers). */
async function readAggregate(teacherId: string): Promise<TeacherRatingAggregate> {
  const teacherRef = firestore.collection("teachers").doc(teacherId);
  const snap = await teacherRef.get();
  const data = snap.data() ?? {};

  const average = Number(data.averageRate);
  const storedCount = Number(data.ratingCount);

  if (Number.isFinite(storedCount) && storedCount >= 0) {
    return {
      teacherId,
      averageRating: Number.isFinite(average) && average > 0 ? average : 0,
      ratingCount: Math.round(storedCount),
    };
  }

  const countSnap = await teacherRef.collection("ratings").count().get();
  const ratingCount = countSnap.data().count;

  // Backfill so the next read is a single document get. Best-effort: a failure
  // only costs another count on the next call.
  if (snap.exists) {
    try {
      await teacherRef.set({ ratingCount }, { merge: true });
    } catch (error) {
      logger.warn(`[ratings] failed backfilling ratingCount teacher=${teacherId}`, error);
    }
  }

  return {
    teacherId,
    averageRating: Number.isFinite(average) && average > 0 ? average : 0,
    ratingCount,
  };
}

function requestedTeacherIds(data: unknown, callerUid: string): string[] {
  const raw = (data as { teacherIds?: unknown } | undefined)?.teacherIds;
  if (!Array.isArray(raw)) return [callerUid];

  const ids = raw
    .filter((id): id is string => typeof id === "string")
    .map((id) => id.trim())
    .filter((id) => id.length > 0);

  // An explicit but empty list means "nothing to look up", not "use the caller".
  return [...new Set(ids)].slice(0, MAX_TEACHERS_PER_CALL);
}

/**
 * Rating aggregates for the named teachers, or for the caller when no ids are
 * given. Unknown ids come back as zeros rather than an error, so a screen that
 * asks about a teacher who has never been rated still renders.
 */
export const teacherRatingSummary = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const teacherIds = requestedTeacherIds(req.data, uid);
  const ratings = await Promise.all(teacherIds.map(readAggregate));

  logger.info(
    `[ratings] teacherRatingSummary caller=${uid} requested=${teacherIds.length} rated=${ratings.filter((r) => r.ratingCount > 0).length}`
  );

  return { ratings };
});
