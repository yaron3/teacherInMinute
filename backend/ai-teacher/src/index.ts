import { config as dotenvConfig } from "dotenv";
dotenvConfig();

import * as admin from "firebase-admin";
import { loadConfig } from "./config";
import { respondToQuestion } from "./respond";

// ─── Bootstrap ───────────────────────────────────────────────────────────────

const config = loadConfig();

const appOptions: admin.AppOptions = { databaseURL: config.firebaseDatabaseUrl };
if (config.firebaseServiceAccount) {
  appOptions.credential = admin.credential.cert(
    config.firebaseServiceAccount as admin.ServiceAccount,
  );
}
// If firebaseServiceAccount is null, Admin SDK uses Application Default Credentials.
admin.initializeApp(appOptions);

console.log("[ai-teacher] Firebase initialised");
console.log(`[ai-teacher] LLM  : ${config.llmModel} @ ${config.llmBaseUrl} (${config.llmApiType})`);
console.log(`[ai-teacher] Delay: ${config.answerDelayMs} ms  |  maxConcurrent: ${config.maxConcurrent}`);

// ─── Concurrency limiter ──────────────────────────────────────────────────────

let active = 0;
const queue: Array<() => void> = [];

function runWhenSlotAvailable(fn: () => Promise<void>): void {
  if (active < config.maxConcurrent) {
    active++;
    fn().finally(() => {
      active--;
      const next = queue.shift();
      if (next) next();
    });
  } else {
    queue.push(() => {
      active++;
      fn().finally(() => {
        active--;
        const next = queue.shift();
        if (next) next();
      });
    });
  }
}

// ─── Question tracker ─────────────────────────────────────────────────────────
// Keeps one pending timer per question to avoid duplicate responses.

const pending = new Map<string, ReturnType<typeof setTimeout>>();

// Ignore questions that were in RTDB before this process started — those are
// either already handled or stale.  Questions created in the last 30 s are
// still eligible (handles a fast restart mid-dispatch wave).
const serviceStartMs = Date.now();
const STARTUP_WINDOW_MS = 30_000;

function shouldIgnoreOnStartup(createdAtMs: number | undefined): boolean {
  if (createdAtMs === undefined) return false; // unknown age → process it
  return createdAtMs < serviceStartMs - STARTUP_WINDOW_MS;
}

function scheduleResponse(
  questionId: string,
  questionData: Record<string, unknown>,
): void {
  if (pending.has(questionId)) return; // already scheduled

  const timer = setTimeout(() => {
    pending.delete(questionId);
    runWhenSlotAvailable(() =>
      respondToQuestion(questionId, questionData, config).catch((err) => {
        console.error(`[ai-teacher] Unhandled error for qid=${questionId}:`, err);
      }),
    );
  }, config.answerDelayMs);

  pending.set(questionId, timer);
  console.log(
    `[ai-teacher] Queued qid=${questionId} topic="${String(questionData.topic ?? "")}" ` +
    `delay=${config.answerDelayMs}ms`,
  );
}

// ─── RTDB listeners ──────────────────────────────────────────────────────────

const db = admin.database();

// Triggered when a question node is created in RTDB.
// createQuestion writes RTDB first (before Firestore), so this fires immediately.
db.ref("questions").on("child_added", (snap) => {
  const qid = snap.key;
  if (!qid) return;

  const q = snap.val() as Record<string, unknown>;
  const status = String(q.status ?? "");
  const conversationType = String(q.conversationType ?? "text");
  const createdAt = typeof q.createdAt === "number" ? q.createdAt : undefined;

  // Only text questions in searching state need an AI response.
  if (status !== "searching") return;
  if (conversationType === "audio" || conversationType === "video") {
    console.log(`[ai-teacher] Skip non-text qid=${qid} type=${conversationType}`);
    return;
  }
  if (shouldIgnoreOnStartup(createdAt)) {
    // Question predates this service instance — already handled or stale.
    return;
  }

  scheduleResponse(qid, q);
});

// Triggered when any question field changes.
// Catches questions that move to "unanswered" after all dispatch waves time out.
// (archiveUnanswered in dispatch.ts updates Firestore status but may also update RTDB.)
db.ref("questions").on("child_changed", (snap) => {
  const qid = snap.key;
  if (!qid) return;
  if (pending.has(qid)) return; // already waiting

  const q = snap.val() as Record<string, unknown>;
  const status = String(q.status ?? "");
  const conversationType = String(q.conversationType ?? "text");

  if (status !== "unanswered") return;
  if (conversationType === "audio" || conversationType === "video") return;

  scheduleResponse(qid, q);
});

// ─── Graceful shutdown ────────────────────────────────────────────────────────

function shutdown(signal: string): void {
  console.log(`[ai-teacher] ${signal} received — shutting down`);
  for (const timer of pending.values()) clearTimeout(timer);
  pending.clear();
  db.goOffline();
  process.exit(0);
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

console.log("[ai-teacher] Watching RTDB questions/ — ready");
