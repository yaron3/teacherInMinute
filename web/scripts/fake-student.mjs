// Plays the student's side of a lesson against the LOCAL EMULATORS, so the web
// teacher flow can be tested without a second device. Refuses any project not
// named demo-*, which the emulators never forward to a real backend.
//
//   node web/scripts/fake-student.mjs ask [topic] [text|audio|video]
//       asks a question, waits (up to 2 minutes) for a teacher to accept,
//       then joins the lesson, reports ready and says hello
//   node web/scripts/fake-student.mjs say "text"   # send a chat message
//   node web/scripts/fake-student.mjs askdraw      # ask the teacher to let them draw
//   node web/scripts/fake-student.mjs draw         # draw a circle on the board
//   node web/scripts/fake-student.mjs media video|audio|text
//   node web/scripts/fake-student.mjs leave        # leave the lesson
//
// Everything goes through the same callables and database paths the apps use;
// only the account setup (role and minutes) is an admin write.

import { initializeApp } from "firebase/app";
import { connectAuthEmulator, createUserWithEmailAndPassword, getAuth, signInWithEmailAndPassword } from "firebase/auth";
import { connectDatabaseEmulator, get, getDatabase, push, ref, serverTimestamp, set } from "firebase/database";
import { connectFunctionsEmulator, getFunctions, httpsCallable } from "firebase/functions";
import { readFileSync, writeFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { tmpdir } from "node:os";
import { join } from "node:path";

const PROJECT = "demo-teacher-in-a-moment";
if (!PROJECT.startsWith("demo-")) throw new Error("emulator projects only");

const EMAIL = "web-fake-student@example.com";
const PASSWORD = "fakestudent123";
const NAME = "Fake Student";
const STATE = join(tmpdir(), "tim-fake-student.json");
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

const student = await signIn();
const command = process.argv[2] ?? "ask";
const call = (name, data) => httpsCallable(fns, name)(data).then((r) => r.data);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

if (command === "ask") {
  const topic = process.argv[3] ?? "algebra";
  const conversationType = process.argv[4] ?? "text";
  // A student with minutes, as onUserCreate and a purchase would leave them.
  await firestorePatch(`users/${student.uid}`, {
    uid: { stringValue: student.uid },
    email: { stringValue: EMAIL },
    fullName: { stringValue: NAME },
    role: { stringValue: "student" },
    remainingMinutes: { integerValue: "30" },
  });
  const created = await call("createQuestion", {
    topic,
    text: "How do I solve 2x + 3 = 11? I keep getting x = 7.",
    photoUrls: [],
    conversationType,
  });
  const qid = created.questionId;
  writeFileSync(STATE, JSON.stringify({ qid }));
  console.log("asked", qid, `(${topic}, ${conversationType}) — accept it in the web app`);

  let status = "searching";
  for (let waited = 0; waited < 120 && status === "searching"; waited++) {
    await sleep(1000);
    status = (await get(ref(db, `questions/${qid}/status`))).val() ?? "gone";
  }
  if (status !== "accepted" && status !== "in_progress") throw new Error(`not accepted: ${status}`);
  console.log("accepted");

  console.log("join ->", JSON.stringify(await call("startLesson", { questionId: qid, ready: false })));
  await set(push(ref(db, `lessonPresence/${qid}/student/connections`)), true);
  await sleep(2000);
  console.log("ready ->", JSON.stringify(await call("startLesson", { questionId: qid, ready: true })));
  await set(push(ref(db, `questions/${qid}/messages`)), {
    text: "Hi! I subtracted 3 and then divided, but I get 7.",
    senderUid: student.uid,
    senderRole: "student",
    createdAt: Date.now(),
    kind: "text",
  });
  console.log("sent hello");
  process.exit(0);
}

const { qid } = JSON.parse(readFileSync(STATE, "utf8"));
const q = (path) => ref(db, `questions/${qid}/${path}`);

if (command === "say") {
  await set(push(q("messages")), { text: process.argv[3] ?? "", senderUid: student.uid, senderRole: "student", createdAt: Date.now(), kind: "text" });
  console.log("sent");
} else if (command === "askdraw") {
  const requestId = randomUUID();
  await set(q("boardPermission"), { status: "requested", requestId, updatedAt: serverTimestamp() });
  console.log("asked to draw", requestId);
} else if (command === "draw") {
  const points = Array.from({ length: 49 }, (_, i) => {
    const a = (i * 2 * Math.PI) / 48;
    return { x: Math.round(1400 + 200 * Math.cos(a)), y: Math.round(600 + 200 * Math.sin(a)) };
  });
  await set(push(q("board/strokes")), { points, createdAt: Date.now(), senderUid: student.uid });
  console.log("drew a circle");
} else if (command === "media") {
  const type = process.argv[3];
  if (!["text", "audio", "video"].includes(type)) throw new Error("media text|audio|video");
  await set(q("conversationType"), type);
  console.log("switched the lesson to", type);
} else if (command === "leave") {
  await set(ref(db, `lessonPresence/${qid}/student/leftAt`), serverTimestamp());
  console.log("student left; endLesson ->", JSON.stringify(await call("endLesson", { questionId: qid })));
} else {
  throw new Error(`unknown command ${command}`);
}
process.exit(0);
