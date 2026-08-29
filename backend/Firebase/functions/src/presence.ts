// ─── Public online-teacher projection ────────────────────────────────────────
//
// Students need to see who is teaching right now, but `teachers/{uid}` cannot
// be opened up for cross-user reads: it also holds `waitingMessages`, which
// carry student names and question topics. Rather than widen that node, the
// backend mirrors the handful of non-sensitive fields into `onlineTeachers`,
// which any signed-in user may read (see database.rules.json).
//
// Only teachers who are actually online appear here — going offline removes the
// entry — so a client reads the node and shows what it finds, with no filtering
// and no per-teacher profile lookup of its own.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onValueWritten } from "firebase-functions/v2/database";

const firestore = admin.firestore();

export const ONLINE_TEACHERS_PATH = "onlineTeachers";

/** The public shape. Deliberately minimal: anything added here becomes visible
 *  to every signed-in user, so it must be safe to show on the student home. */
export interface OnlineTeacherProjection {
  subjects: string[];
  displayName: string;
  photoUrl: string;
  /** When the teacher came online, for ordering and staleness checks. */
  since: number;
}

function database() {
  return admin.database();
}

/**
 * Rewrites (or clears) one teacher's public entry from their current presence.
 *
 * Reads rather than trusts the triggering event, so concurrent status and
 * subject writes converge on the same answer whichever order they land in.
 */
export async function republishTeacherPresence(uid: string): Promise<boolean> {
  const teacherSnap = await database().ref(`teachers/${uid}`).get();
  const status = teacherSnap.child("status").val();
  const entryRef = database().ref(`${ONLINE_TEACHERS_PATH}/${uid}`);

  if (status !== "online") {
    await entryRef.remove();
    logger.info(`[presence] cleared online entry uid=${uid}`);
    return false;
  }

  const rawSubjects = teacherSnap.child("subjects").val();
  const subjects = Array.isArray(rawSubjects)
    ? rawSubjects.filter((s): s is string => typeof s === "string")
    : [];

  // Name and photo live in Firestore; copying them here is what lets the client
  // render the grid without reading other users' documents.
  const userSnap = await firestore.collection("users").doc(uid).get();
  const user = userSnap.data() ?? {};
  const displayName = typeof user.fullName === "string" ? user.fullName : "";
  const photoUrl =
    (typeof user.profileImageURL === "string" && user.profileImageURL) ||
    (typeof user.profilePhotoURL === "string" && user.profilePhotoURL) ||
    (typeof user.photoURL === "string" && user.photoURL) ||
    "";

  // Preserve the original `since` while a teacher stays online, so a subjects
  // edit does not make them look newly available.
  const existingSince = (await entryRef.child("since").get()).val();
  const since = typeof existingSince === "number" ? existingSince : Date.now();

  const projection: OnlineTeacherProjection = { subjects, displayName, photoUrl, since };
  await entryRef.set(projection);

  logger.info(`[presence] published online entry uid=${uid} subjects=${subjects.length}`);
  return true;
}

/** Mirrors a teacher going on- or offline. */
export const onTeacherPresenceStatusWritten = onValueWritten(
  "teachers/{uid}/status",
  async (event) => {
    const uid = event.params.uid;
    try {
      await republishTeacherPresence(uid);
    } catch (err) {
      logger.error(`[presence] failed publishing uid=${uid}`, err);
    }
  }
);

/** Keeps a published entry's subjects current while the teacher stays online. */
export const onTeacherPresenceSubjectsWritten = onValueWritten(
  "teachers/{uid}/subjects",
  async (event) => {
    const uid = event.params.uid;
    try {
      await republishTeacherPresence(uid);
    } catch (err) {
      logger.error(`[presence] failed publishing subjects uid=${uid}`, err);
    }
  }
);

/**
 * Rebuilds every entry from the authoritative `teachers` node.
 *
 * Needed once when the projection is introduced — teachers who are already
 * online will not write `status` again, so nothing would trigger their entry —
 * and useful afterwards to repair drift.
 */
export async function republishAllTeacherPresence(): Promise<number> {
  const snapshot = await database().ref("teachers").get();
  const uids: string[] = [];
  snapshot.forEach((child) => {
    if (child.key) uids.push(child.key);
    return false;
  });

  let onlineCount = 0;
  for (const uid of uids) {
    try {
      if (await republishTeacherPresence(uid)) onlineCount += 1;
    } catch (err) {
      logger.error(`[presence] backfill failed uid=${uid}`, err);
    }
  }

  logger.info(`[presence] backfill complete teachers=${uids.length} online=${onlineCount}`);
  return onlineCount;
}
