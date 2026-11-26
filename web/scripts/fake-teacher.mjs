// Plays the teacher's side of a lesson against the LOCAL EMULATORS, so the web
// student flow can be tested without a second device. Refuses any project not
// named demo-*, which the emulators never forward to a real backend.
//
//   node web/scripts/fake-teacher.mjs            # accept the newest searching question
//   node web/scripts/fake-teacher.mjs leave      # then leave the lesson it accepted
//
// Accepting is faked with admin writes (the real path, acceptInvite, needs the
// teacher to have been dispatched an invite). Everything after that goes through
// the same callables and RTDB paths the apps use.

import { initializeApp } from "firebase/app";
import { connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signInWithEmailAndPassword } from "firebase/auth";
import { connectDatabaseEmulator, getDatabase, push, ref, serverTimestamp, set } from "firebase/database";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT = "demo-teacher-in-a-moment";
if (!PROJECT.startsWith("demo-")) throw new Error("emulator projects only");

const EMAIL = "web-fake-teacher@example.com";
const PASSWORD = "faketeacher123";
const NAME = "Fake Teacher";
const STATE = join(tmpdir(), "tim-fake-teacher.json");
const OWNER = { Authorization: "Bearer owner", "Content-Type": "application/json" };

const app = initializeApp({ apiKey: "x", projectId: PROJECT, databaseURL: `https://${PROJECT}.firebaseio.com` });
const auth = getAuth(app);
const db = getDatabase(app);
const fns = getFunctions(app, "us-central1");
connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
connectDatabaseEmulator(db, "127.0.0.1", 9000);
connectFunctionsEmulator(fns, "127.0.0.1", 5001);

async function signIn() {
  try {
    return (await signInWithEmailAndPassword(auth, EMAIL, PASSWORD)).user;
  } catch {
    return (await createUserWithEmailAndPassword(auth, EMAIL, PASSWORD)).user;
  }
}

async function firestorePatch(path, fields) {
  const mask = Object.keys(fields).map((f) => `updateMask.fieldPaths=${f}`).join("&");
  const res = await fetch(
    `http://127.0.0.1:8085/v1/projects/${PROJECT}/databases/(default)/documents/${path}?${mask}`,
    { method: "PATCH", headers: OWNER, body: JSON.stringify({ fields }) },
  );
  if (!res.ok) throw new Error(`firestore ${path}: ${res.status} ${await res.text()}`);
}

async function rtdbPatch(path, value) {
  const res = await fetch(`http://127.0.0.1:9000/${path}.json?ns=${PROJECT}`, {
    method: "PATCH",
    headers: OWNER,
    body: JSON.stringify(value),
  });
  if (!res.ok) throw new Error(`rtdb ${path}: ${res.status}`);
}

async function newestSearchingQuestion() {
  const res = await fetch(`http://127.0.0.1:9000/questions.json?ns=${PROJECT}`, { headers: OWNER });
  const rows = Object.entries((await res.json()) ?? {}).filter(([, q]) => q.status === "searching");
  rows.sort(([, a], [, b]) => (b.createdAt ?? 0) - (a.createdAt ?? 0));
  return rows[0]?.[0];
}

const teacher = await signIn();
const str = (v) => ({ stringValue: v });

if (process.argv[2] === "leave") {
  const { qid } = JSON.parse(readFileSync(STATE, "utf8"));
  await set(ref(db, `lessonPresence/${qid}/teacher/leftAt`), serverTimestamp());
  const result = await httpsCallable(fns, "endLesson")({ questionId: qid });
  console.log("teacher left; endLesson ->", JSON.stringify(result.data));
  process.exit(0);
}

const qid = await newestSearchingQuestion();
if (!qid) throw new Error("no searching question — ask one in the web app first");

await firestorePatch(`users/${teacher.uid}`, {
  uid: str(teacher.uid), role: str("teacher"), fullName: str(NAME), email: str(EMAIL),
});
// The fields acceptInvite writes; endLesson refuses to settle a question
// without acceptedAt.
await firestorePatch(`questions/${qid}`, {
  status: str("accepted"),
  acceptedByTeacher: str(teacher.uid),
  acceptedAt: { timestampValue: new Date().toISOString() },
});
await rtdbPatch(`questions/${qid}`, {
  status: "accepted",
  teacherId: teacher.uid,
  acceptedByTeacher: teacher.uid,
  acceptedAt: Date.now(),
  teacherName: NAME,
});
// The teacher's own LiveKit credentials, as the apps fetch them after accepting.
const media = (await httpsCallable(fns, "getQuestionStatus")({ questionId: qid })).data;
writeFileSync(STATE, JSON.stringify({ qid, liveKitRoom: media.liveKitRoom, liveKitToken: media.liveKitToken }));
console.log("accepted", qid, media.liveKitToken ? `(LiveKit token for ${media.liveKitRoom} saved to ${STATE})` : "");

const start = httpsCallable(fns, "startLesson");
console.log("join ->", JSON.stringify((await start({ questionId: qid, ready: false })).data));
await set(push(ref(db, `lessonPresence/${qid}/teacher/connections`)), true);
// Give the student a moment to connect first, as a real teacher's app would.
await new Promise((r) => setTimeout(r, 4000));
console.log("ready ->", JSON.stringify((await start({ questionId: qid, ready: true })).data));

await set(push(ref(db, `questions/${qid}/messages`)), {
  text: "Hi! Let's look at it together. What did you try first?",
  senderUid: teacher.uid,
  senderRole: "teacher",
  createdAt: Date.now(),
  kind: "text",
});
console.log("sent greeting");
process.exit(0);
