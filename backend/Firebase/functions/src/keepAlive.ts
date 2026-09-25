// ─── Teacher keep-alive ──────────────────────────────────────────────────────
//
// `status: "online"` says a teacher wants questions. It cannot say whether
// their app is still there to show one. So while a teacher is online the app
// writes `teachers/{uid}/lastSeenAt` once a minute — on the server's clock,
// which the database rules insist on — and an app that has been silent for
// KEEPALIVE_TIMEOUT_SECONDS is taken to be gone: killed, crashed, suspended in
// the background, or off the network.
//
// Gone is not the same as unreachable. A teacher with a push token is still
// sent questions — a push is how a backgrounded teacher hears of one anyway —
// so they stay online. A teacher without one has no way left to hear about a
// question, so this takes them offline: out of dispatch, and, through
// ./presence, out of the `onlineTeachers` list students see. Each keep-alive
// re-sends `status: "online"`, so a running app puts its teacher back within a
// minute, and at once when it returns to the foreground.
//
// This replaces the apps' `onDisconnect` handler, which set `status:
// "offline"` whenever the socket closed. That took a teacher out of the pool
// with no regard for whether a push could still reach them.
//
// ./scoring applies the same rule when ranking, so dispatch skips a silent
// teacher from the moment the timeout passes rather than from the next sweep.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";

import { isTeacherReachable } from "./scoring";
import { TeacherRecord } from "./types";

function database() {
  return admin.database();
}

/**
 * Sets `status: "offline"`, but only if the teacher is still online and still
 * out of reach when the write lands. A keep-alive arriving between the sweep's
 * read and this write means the app is back, and it has to win.
 */
async function takeOfflineIfStillUnreachable(uid: string): Promise<boolean> {
  let takingOffline = false;
  const result = await database()
    .ref(`teachers/${uid}`)
    .transaction((current: TeacherRecord | null) => {
      takingOffline = false;
      // The first pass runs against the local cache, which on a server is
      // usually empty. Aborting there would never see the real value; handing
      // back what is there lets it arrive for the retry.
      if (current === null) return current;
      if (current.status !== "online" || isTeacherReachable(current)) return undefined;
      takingOffline = true;
      return { ...current, status: "offline" };
    });
  return result.committed && takingOffline;
}

/**
 * Takes offline every online teacher who is out of reach — silent past the
 * keep-alive timeout, with no push token to fall back on — and returns who.
 */
export async function takeUnreachableTeachersOffline(): Promise<string[]> {
  // The same indexed query dispatch uses: only online teachers can be out of
  // reach, and the node holds every teacher who has ever signed up.
  const snapshot = await database()
    .ref("teachers")
    .orderByChild("status")
    .equalTo("online")
    .once("value");
  const online = (snapshot.val() as Record<string, TeacherRecord> | null) ?? {};

  const now = Date.now();
  const unreachable = Object.entries(online)
    .filter(([, teacher]) => !isTeacherReachable(teacher, now))
    .map(([uid]) => uid);

  const takenOffline: string[] = [];
  for (const uid of unreachable) {
    try {
      if (await takeOfflineIfStillUnreachable(uid)) {
        takenOffline.push(uid);
        logger.info(`[keepAlive] took teacher offline uid=${uid} reason=silent-without-push`);
      }
    } catch (err) {
      logger.error(`[keepAlive] failed taking teacher offline uid=${uid}`, err);
    }
  }

  logger.info(
    `[keepAlive] sweep online=${Object.keys(online).length} unreachable=${unreachable.length} takenOffline=${takenOffline.length}`
  );
  return takenOffline;
}

/** Runs the sweep once a minute — the finest schedule Cloud Scheduler has. */
export const teacherKeepAliveWatchdog = onSchedule("every 1 minutes", async () => {
  await takeUnreachableTeachersOffline();
});
