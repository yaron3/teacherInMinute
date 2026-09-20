#!/usr/bin/env node
/**
 * Drops subject areas whose stored subtopics match nothing in the app's
 * catalog.
 *
 * Two teacher profiles carried `Computer_Science: ["הכל"]` — "All" in Hebrew,
 * written by an older build that stored the localized label instead of the
 * English key. The catalog has no such subtopic (Computer Science offers only
 * "Programming"), so the value could not be translated on the way out and the
 * English teacher home rendered "Computer Science: הכל". It could not round-trip
 * through the subject picker either: an unknown subtopic cannot be ticked, so
 * saving that sheet would silently drop it anyway.
 *
 * The write path has since been fixed to store English titles and keys
 * (TeacherSubjectsViewModel), so this is cleanup of legacy rows, not a
 * workaround for a live bug. Nothing here maps the old value onto a real
 * subtopic: "All" was never a subtopic, and inventing one would put a claim on
 * a teacher's profile that they never made.
 *
 * Idempotent — an account already cleaned is skipped. Dry run by default:
 *
 *   node scripts/drop-orphaned-subject-areas.js            # report only
 *   node scripts/drop-orphaned-subject-areas.js --apply    # write
 */
const admin = require("firebase-admin");
const path = require("path");

const SERVICE_ACCOUNT = path.join(
  __dirname,
  "..",
  "teacher-in-a-moment-firebase-adminsdk-fbsvc-690805d9d8.json"
);

// Areas to drop, with the exact orphaned subtopic that identifies them. Keyed
// by the `subjectSelections` map key; the two parallel arrays a profile also
// keeps use different spellings, hence both forms.
const ORPHANS = [
  {
    selectionKey: "Computer_Science",
    orphanSubtopic: "הכל",
    areaId: "computerscience",
    areaTitle: "Computer_Science",
  },
];

const apply = process.argv.includes("--apply");

async function main() {
  admin.initializeApp({
    credential: admin.credential.cert(require(SERVICE_ACCOUNT)),
  });
  const db = admin.firestore();
  const FV = admin.firestore.FieldValue;

  const snap = await db.collection("users").where("role", "==", "teacher").get();
  let affected = 0;

  for (const doc of snap.docs) {
    const selections = doc.get("subjectSelections") || {};
    for (const orphan of ORPHANS) {
      const subtopics = selections[orphan.selectionKey];
      if (!Array.isArray(subtopics)) continue;
      // Only touch rows whose subtopics are exactly the orphan. A profile that
      // has since picked real subtopics for this area is left alone.
      if (!subtopics.every((s) => s === orphan.orphanSubtopic)) continue;

      affected++;
      console.log(
        `${apply ? "dropping" : "would drop"} ${orphan.selectionKey} from ` +
          `${doc.id} (${doc.get("fullName") || "?"}) — was ${JSON.stringify(subtopics)}`
      );

      if (!apply) continue;
      await doc.ref.update({
        [`subjectSelections.${orphan.selectionKey}`]: FV.delete(),
        subjectAreaIDs: FV.arrayRemove(orphan.areaId),
        subjectAreas: FV.arrayRemove(orphan.areaTitle),
      });
    }
  }

  console.log(
    `\n${snap.size} teacher profile(s) scanned, ${affected} ${apply ? "updated" : "would be updated"}.`
  );
  if (!apply && affected) console.log("Re-run with --apply to write.");
  process.exit(0);
}

main().catch((err) => {
  console.error("FAILED:", err.message);
  process.exit(1);
});
