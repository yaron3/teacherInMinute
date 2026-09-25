// ─── Teacher busy state ──────────────────────────────────────────────────────
//
// A teacher in a session is still online — their app is connected, and they
// will want questions again the moment it ends — but they cannot take one now.
// So busy is its own fact, kept at `teachers/{uid}/busy` beside `status` rather
// than folded into it: the apps write `status` — every keep-alive re-sends it —
// and so does ./keepAlive when an app goes silent mid-lesson, and either would
// silently overwrite a "busy" there. `busy` is written by the backend alone.
//
// Set when a teacher accepts a question; cleared by every path that ends that
// session — endLesson, forceEndLesson, endAbandonedLesson, and cancelQuestion
// on an accepted question. rankTeachers skips a busy teacher, which keeps them
// out of new waves, backfills and replacement invites alike.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

import { TeacherBusy } from "./types";

function busyRef(teacherUid: string) {
  return admin.database().ref(`teachers/${teacherUid}/busy`);
}

export async function markTeacherBusy(teacherUid: string, questionId: string): Promise<void> {
  const busy: TeacherBusy = { questionId, since: Date.now() };
  await busyRef(teacherUid).set(busy);
  logger.info(`[busy] teacher=${teacherUid} busy with qid=${questionId}`);
}

/**
 * Clears the mark, but only if it is still for this question.
 *
 * A session can be ended twice — both apps call endLesson, and the hard-cap and
 * abandoned-lesson tasks can fire after it — and a late clear must not free a
 * teacher who has since moved on to a different session.
 */
export async function releaseTeacherBusy(teacherUid: string, questionId: string): Promise<void> {
  if (!teacherUid) return;

  let cleared = false;
  // Never aborts: the first pass runs against the local cache, which on a
  // server is usually empty, and aborting there would never see the real value.
  // Writing back what is there is a no-op that lets the retry happen.
  await busyRef(teacherUid).transaction((current: TeacherBusy | null) => {
    cleared = current !== null && current.questionId === questionId;
    return cleared ? null : current;
  });

  logger.info(`[busy] teacher=${teacherUid} release for qid=${questionId} cleared=${cleared}`);
}
