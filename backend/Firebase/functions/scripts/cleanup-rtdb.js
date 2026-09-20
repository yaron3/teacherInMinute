#!/usr/bin/env node
/**
 * Clears out of the realtime database what is no longer true.
 *
 * RTDB is the live layer: who is teaching right now, and which lessons are
 * running. Everything settled belongs in Firestore, and everything stale is
 * worse than absent — a teacher who looks online is dispatched questions that
 * reach nobody, and each wave they are picked for burns its timeout before
 * moving on. A demo account sat "online" for two days that way (bugs.md #1).
 *
 * ── The three states a teacher can be in ──────────────────────────────────
 *
 *   online   availability=available, status=online
 *            The app is running and the toggle is on. Takes questions.
 *
 *   offline  availability=available, status=offline
 *            The toggle is on but the app is not connected — killed, crashed,
 *            or out of signal, so the dead man's switch flipped `status`. They
 *            still mean to be available, so the record stays and keeps its
 *            push token.
 *
 *   dnd      availability=dnd
 *            The toggle is off, whatever the app is doing. Nothing here is
 *            worth keeping: the record goes, and the FCM token is copied into
 *            the teacher's Firestore user document first so the address
 *            survives — RTDB is where it lived, and it is only rewritten at
 *            sign-in or on a token refresh.
 *
 * `availability` is written only when the teacher works the toggle;
 * `onDisconnect` writes `status` alone. That is what tells the second state
 * from the third, and records written before this existed carry neither —
 * see `--sweep-legacy`.
 *
 * Four passes: teachers, the onlineTeachers projection, live questions whose
 * lesson already settled into Firestore, and invites for questions that are
 * over.
 *
 * Dry run by default:
 *
 *   node scripts/cleanup-rtdb.js                    # report only
 *   node scripts/cleanup-rtdb.js --apply            # write
 *   node scripts/cleanup-rtdb.js --stale-hours=6    # stricter staleness
 *   node scripts/cleanup-rtdb.js --sweep-legacy     # see below
 *
 * `--sweep-legacy` treats a record with no `availability` as don't-disturb: a
 * one-off for what accumulated before the apps wrote intent. A teacher who had
 * merely left the toggle on is evicted by it and returns when they next open
 * the app.
 */
const admin = require("firebase-admin");
const path = require("path");

const SERVICE_ACCOUNT = path.join(
  __dirname,
  "..",
  "teacher-in-a-moment-firebase-adminsdk-fbsvc-690805d9d8.json"
);

const DATABASE_URL = "https://teacher-in-a-moment-default-rtdb.firebaseio.com";

/** A question in one of these states is finished: whatever it was doing in the
 *  realtime layer is over, and endLesson has already copied it to Firestore. */
const TERMINAL_STATUSES = new Set(["completed", "cancelled", "canceled", "unanswered"]);

/** How long a question with no Firestore document at all may linger before it
 *  counts as debris. Anything live has a document from createQuestion, so this
 *  only catches writes that lost their other half. */
const ORPHAN_QUESTION_HOURS = 24;

/**
 * After this, an `accepted` question that never became a lesson is written off.
 *
 * Nothing used to call startLesson, so a teacher's accept was the last thing
 * that ever happened to these: no lesson document, no hard cap — that task is
 * armed by startLesson — and no end. They sit accepted for good. The backend
 * now ends such a lesson itself after a couple of minutes
 * (endAbandonedLesson), so this only clears what accumulated before that, and
 * settles them the same way: cancelled, by the system, charged to nobody,
 * because nothing was taught.
 */
const STUCK_ACCEPTED_HOURS = 24;

const apply = process.argv.includes("--apply");
const sweepLegacy = process.argv.includes("--sweep-legacy");
const staleHours = readNumberFlag("--stale-hours", 12);

function readNumberFlag(name, fallback) {
  const arg = process.argv.find((value) => value.startsWith(`${name}=`));
  if (!arg) return fallback;
  const parsed = Number(arg.slice(name.length + 1));
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function millis(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n <= 0) return undefined;
  // Seconds and milliseconds are both in the wild.
  return n < 1e12 ? n * 1000 : n;
}

function hoursAgo(ms) {
  return (Date.now() - ms) / 3_600_000;
}

async function main() {
  admin.initializeApp({
    credential: admin.credential.cert(require(SERVICE_ACCOUNT)),
    databaseURL: DATABASE_URL,
  });

  const db = admin.database();
  const firestore = admin.firestore();

  console.log(
    `${apply ? "APPLYING" : "DRY RUN"} — stale after ${staleHours}h` +
      `${sweepLegacy ? ", sweeping records that predate `availability`" : ""}\n`
  );

  const teachers = await cleanTeachers(db, firestore);
  const removedProjections = await cleanOnlineTeachers(db);
  const { removedQuestions, keptQuestions } = await cleanQuestions(db, firestore);
  const removedInvites = await cleanTeacherInvites(db, firestore);

  console.log("\n─── summary ───");
  console.log(`teachers removed (dnd) ${teachers.removed}`);
  console.log(`presence demoted       ${teachers.demoted} (online but idle)`);
  console.log(`teachers kept          ${teachers.kept} (online or offline with the toggle on)`);
  if (teachers.legacy) {
    console.log(`teachers unclassified  ${teachers.legacy} — re-run with --sweep-legacy`);
  }
  console.log(`onlineTeachers cleared ${removedProjections}`);
  console.log(`questions removed      ${removedQuestions} (${keptQuestions} still live)`);
  console.log(`invites removed        ${removedInvites}`);
  if (!apply) console.log("\nNothing was written. Re-run with --apply.");
  process.exit(0);
}

/** Which of the three states this record is in, or `legacy` when it predates
 *  the apps writing intent at all. */
function classify(record) {
  const availability = record?.availability;
  const status = record?.status;
  const activeAt = millis(record?.lastActiveAt);

  if (availability === "dnd") return { state: "dnd", detail: "toggle off" };

  if (availability === "available") {
    if (status !== "online") return { state: "offline", detail: "toggle on, app not connected" };
    if (activeAt !== undefined && hoursAgo(activeAt) > staleHours) {
      return { state: "stale", detail: `online but idle ${Math.round(hoursAgo(activeAt))}h` };
    }
    return { state: "online", detail: "" };
  }

  return { state: "legacy", detail: `no availability (status=${status ?? "none"})` };
}

/**
 * Applies the three states.
 *
 * A record claiming "online" with no sign of life is not online: the app died
 * without its onDisconnect firing. That is the second state, not a reason to
 * delete anything, so its `status` is corrected rather than the record removed.
 *
 * A record with no `lastActiveAt` is taken at its word. iOS never writes one —
 * TeacherPresenceService publishes availability, status and subjects only — so
 * treating its absence as staleness would evict live iOS teachers.
 */
async function cleanTeachers(db, firestore) {
  const snapshot = await db.ref("teachers").get();
  const teachers = snapshot.val() || {};
  const counts = { removed: 0, demoted: 0, kept: 0, legacy: 0 };
  const unknownAge = [];

  for (const [uid, record] of Object.entries(teachers)) {
    const { state, detail } = classify(record);
    const name = record?.displayName || "?";

    if (state === "online" || state === "offline") {
      counts.kept += 1;
      if (state === "online" && millis(record?.lastActiveAt) === undefined) {
        unknownAge.push(`${uid} (${name})`);
      }
      continue;
    }

    if (state === "stale") {
      console.log(
        `${apply ? "demoting" : "would demote"} teachers/${uid} (${name}) — ${detail}, ` +
          "leaving the toggle on"
      );
      counts.demoted += 1;
      if (apply) {
        await db.ref(`teachers/${uid}`).update({ status: "offline", isOnline: false });
      }
      continue;
    }

    // A record with no intent but a live-looking status is never swept. The
    // sweep guesses "don't disturb" from the absence of a field, and guessing
    // that about someone who is advertised as online right now would drop a
    // teacher out of the pool mid-session. They classify themselves the next
    // time they touch the toggle.
    if (state === "legacy" && record?.status === "online") {
      console.log(`leaving teachers/${uid} (${name}) — ${detail}, looks online`);
      counts.legacy += 1;
      continue;
    }

    if (state === "legacy" && !sweepLegacy) {
      console.log(`leaving teachers/${uid} (${name}) — ${detail}`);
      counts.legacy += 1;
      continue;
    }

    // dnd, or legacy being swept: the record goes, the address is kept.
    const token = record?.fcmToken;
    console.log(
      `${apply ? "removing" : "would remove"} teachers/${uid} (${name}) — ` +
        `${state === "legacy" ? `${detail}, swept as dnd` : detail}` +
        `${token ? ", moving fcmToken to Firestore" : ", no token to move"}`
    );
    counts.removed += 1;
    if (!apply) continue;

    if (token) await moveTokenToFirestore(firestore, uid, record);
    await db.ref(`teachers/${uid}`).remove();
  }

  if (unknownAge.length) {
    // Worth reading rather than skimming: these are advertised as available, so
    // if one is stale, real questions are being dispatched to nobody.
    console.log(
      `\n  note: ${unknownAge.length} teacher(s) are online with no lastActiveAt, so their\n` +
        "  presence cannot be aged out here — iOS never writes one. Check them by hand:\n    " +
        unknownAge.join("\n    ") +
        "\n"
    );
  }
  return counts;
}

/**
 * Keeps the push address when the presence record goes.
 *
 * The token is written to RTDB at sign-in and on refresh, nowhere else, so
 * deleting the record would lose the only copy until the teacher signed in
 * again — reachable with the app open and not otherwise, which is the defect in
 * bugs.md #13/#14 reintroduced by a cleanup.
 */
async function moveTokenToFirestore(firestore, uid, record) {
  const payload = {
    fcmToken: record.fcmToken,
    fcmTokenMovedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  const updatedAt = millis(record.fcmTokenUpdatedAt);
  if (updatedAt !== undefined) {
    payload.fcmTokenUpdatedAt = admin.firestore.Timestamp.fromMillis(updatedAt);
  }
  // A teacher with more than one device has a token per device; keeping the map
  // loses nothing and costs a field.
  if (record.devices && typeof record.devices === "object") {
    payload.fcmDevices = record.devices;
  }
  await firestore.collection("users").doc(uid).set(payload, { merge: true });
}

/** The public projection should name exactly the teachers who are online. */
async function cleanOnlineTeachers(db) {
  const [projectionSnap, teachersSnap] = await Promise.all([
    db.ref("onlineTeachers").get(),
    db.ref("teachers").get(),
  ]);

  const projection = projectionSnap.val() || {};
  const teachers = teachersSnap.val() || {};
  let removed = 0;

  for (const uid of Object.keys(projection)) {
    if (teachers[uid]?.status === "online") continue;
    console.log(`${apply ? "clearing" : "would clear"} onlineTeachers/${uid} — not online`);
    removed += 1;
    if (apply) await db.ref(`onlineTeachers/${uid}`).remove();
  }
  return removed;
}

/**
 * Drops live question nodes whose lesson is over.
 *
 * Firestore is the authority: endLesson copies the node across and then removes
 * it, so anything still here whose document reads terminal is a removal that
 * did not happen — the function died between the two, or an older build never
 * did it at all.
 */
async function cleanQuestions(db, firestore) {
  const snapshot = await db.ref("questions").get();
  const questions = snapshot.val() || {};
  let removedQuestions = 0;
  let keptQuestions = 0;
  let settledQuestions = 0;
  const stillRunning = [];

  for (const [qid, node] of Object.entries(questions)) {
    const docRef = firestore.collection("questions").doc(qid);
    const doc = await docRef.get();
    const status = doc.exists ? doc.get("status") : undefined;
    const startedAt = millis(node?.createdAt) ?? doc.get?.("createdAt")?.toMillis?.();
    const ageHours = startedAt === undefined ? undefined : hoursAgo(startedAt);

    let reason;
    let settle = false;

    if (doc.exists) {
      if (TERMINAL_STATUSES.has(status)) {
        reason = `firestore says ${status}`;
      } else if (
        status === "accepted" &&
        !doc.get("lessonId") &&
        ageHours !== undefined &&
        ageHours > STUCK_ACCEPTED_HOURS
      ) {
        reason = `accepted ${Math.round(ageHours)}h ago and never started`;
        settle = true;
      } else if (ageHours !== undefined && ageHours > STUCK_ACCEPTED_HOURS) {
        // In progress and ancient: a lesson may genuinely have happened, and
        // settling it would decide what it cost. Left for a person.
        stillRunning.push(`${qid} (${status}, ${Math.round(ageHours)}h)`);
        keptQuestions += 1;
        continue;
      }
    } else {
      const wroteAt = millis(node?.updatedAt) ?? millis(node?.createdAt);
      if (wroteAt === undefined || hoursAgo(wroteAt) > ORPHAN_QUESTION_HOURS) {
        reason = "no firestore document";
      }
    }

    if (!reason) {
      keptQuestions += 1;
      continue;
    }

    console.log(
      `${apply ? "removing" : "would remove"} questions/${qid} — ${reason}` +
        `${settle ? ", settling it as cancelled" : ""}`
    );
    removedQuestions += 1;
    if (settle) settledQuestions += 1;
    if (!apply) continue;

    if (settle) {
      await docRef.set(
        {
          status: "cancelled",
          endedBy: "system",
          endedReason: "never_started",
          endedAt: admin.firestore.FieldValue.serverTimestamp(),
          billedSeconds: 0,
          durationSeconds: 0,
          cost: 0,
          teacherEarnings: 0,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    }
    await db.ref(`questions/${qid}`).remove();
  }

  if (stillRunning.length) {
    console.log(
      `\n  note: ${stillRunning.length} question(s) are old but in progress, so what they\n` +
        "  cost is a judgment call and they were left alone:\n    " +
        stillRunning.join("\n    ") +
        "\n"
    );
  }
  if (settledQuestions) {
    console.log(
      `\n  ${settledQuestions} of those also get a Firestore write — they were accepted but\n` +
        "  never started, so they are closed as cancelled with nothing charged.\n"
    );
  }

  return { removedQuestions, keptQuestions };
}

/**
 * Clears invites for questions that are over.
 *
 * The teacher's dashboard watches `teacherInvites/{uid}`, so a leftover here is
 * not merely stale data: it is a card offering a question nobody can accept.
 */
async function cleanTeacherInvites(db, firestore) {
  const snapshot = await db.ref("teacherInvites").get();
  const invites = snapshot.val() || {};
  const statusCache = new Map();
  let removed = 0;

  for (const [uid, questionMap] of Object.entries(invites)) {
    for (const qid of Object.keys(questionMap || {})) {
      if (!statusCache.has(qid)) {
        const doc = await firestore.collection("questions").doc(qid).get();
        statusCache.set(qid, doc.exists ? doc.get("status") : "missing");
      }
      const status = statusCache.get(qid);
      if (status !== "missing" && !TERMINAL_STATUSES.has(status)) continue;

      console.log(
        `${apply ? "removing" : "would remove"} teacherInvites/${uid}/${qid} — ${status}`
      );
      removed += 1;
      if (apply) await db.ref(`teacherInvites/${uid}/${qid}`).remove();
    }
  }
  return removed;
}

main().catch((err) => {
  console.error("FAILED:", err.message);
  process.exit(1);
});
