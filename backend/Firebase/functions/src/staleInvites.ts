// ─── Stale question sweep ────────────────────────────────────────────────────
//
// The safety net behind questionWatchdog and the cleanup in each path that ends
// a question. Once a minute it removes every invite card whose search ended
// more than STALE_GRACE_SECONDS ago (search length is
// question_search_timeout_seconds, 90 s by default), and declares unanswered
// any question still searching past that point, such as one whose watchdog
// task was never enqueued or failed both attempts.
//
// A card that outlives its question shows on the teacher's dashboard with an
// ever-growing waiting counter, and nothing else will ever remove it: the
// client keeps a card for as long as its RTDB node exists (see InviteService).
// Expired cards are safe to remove whatever their question's state:
// acceptInvite refuses an invite past its expiresAt.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { archiveUnanswered } from "./dispatch";
import { INVITE_EXPIRY_SECONDS, QuestionDoc } from "./types";

/** How long past its search's end a card or question is left for the regular
 *  cleanup (the watchdog fires right at the end) before the sweep steps in. */
export const STALE_GRACE_SECONDS = 30;

/** teacherInvites as stored: teacher uid → question id → card. */
type InviteTree = Record<string, Record<string, { expiresAt?: unknown } | null> | null>;

/** The `teacherInvites/{uid}/{qid}` paths whose card expired before `cutoff`
 *  (Unix ms). A card without a numeric expiresAt is left alone: the app does
 *  not show one. */
export function expiredInvitePaths(tree: InviteTree | null, cutoff: number): string[] {
  const paths: string[] = [];
  for (const [uid, cards] of Object.entries(tree ?? {})) {
    for (const [qid, card] of Object.entries(cards ?? {})) {
      const expiresAt = card?.expiresAt;
      if (typeof expiresAt === "number" && expiresAt < cutoff) {
        paths.push(`teacherInvites/${uid}/${qid}`);
      }
    }
  }
  return paths;
}

/** When a searching question's search ended, in Unix ms: its own searchEndsAt,
 *  or INVITE_EXPIRY_SECONDS after it was created for one without (a demo
 *  question, or one from before searchEndsAt existed). Null if it carries
 *  neither, which leaves it alone. */
export function searchEndedAtMillis(question: Pick<QuestionDoc, "searchEndsAt" | "createdAt">): number | null {
  if (question.searchEndsAt) return question.searchEndsAt.toMillis();
  if (question.createdAt) return question.createdAt.toMillis() + INVITE_EXPIRY_SECONDS * 1000;
  return null;
}

export async function sweepStaleQuestions(now = Date.now()): Promise<{
  invitesRemoved: number;
  questionsArchived: number;
}> {
  const cutoff = now - STALE_GRACE_SECONDS * 1000;
  const db = admin.database();
  const firestore = admin.firestore();

  // Questions first: archiving one removes its cards too, so the card pass
  // below only has strays left to find.
  //
  // Queried on status alone, which needs no composite index; only a handful of
  // questions are ever searching at once.
  const searching = await firestore.collection("questions").where("status", "==", "searching").get();
  let questionsArchived = 0;
  for (const doc of searching.docs) {
    const question = doc.data() as QuestionDoc;
    const endedAt = searchEndedAtMillis(question);
    if (endedAt === null || endedAt >= cutoff) continue;
    logger.warn(
      `[staleSweep] qid=${doc.id} still searching ${Math.round((now - endedAt) / 1000)}s after its search ended — archiving`
    );
    if (await archiveUnanswered(doc.id, question.alreadyInvited ?? [])) questionsArchived += 1;
  }

  const tree = (await db.ref("teacherInvites").once("value")).val() as InviteTree | null;
  const stale = expiredInvitePaths(tree, cutoff);
  for (const path of stale) logger.warn(`[staleSweep] removing expired invite card ${path}`);
  await Promise.all(stale.map((path) => db.ref(path).remove()));

  if (stale.length > 0 || questionsArchived > 0) {
    logger.warn(`[staleSweep] invitesRemoved=${stale.length} questionsArchived=${questionsArchived}`);
  }
  return { invitesRemoved: stale.length, questionsArchived };
}

/** Runs the sweep once a minute — the finest schedule Cloud Scheduler has. */
export const staleQuestionSweep = onSchedule("every 1 minutes", async () => {
  await sweepStaleQuestions();
});
