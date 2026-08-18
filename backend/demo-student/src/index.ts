import { config as dotenvConfig } from "dotenv";
dotenvConfig();

import * as admin from "firebase-admin";

import { loadConfig } from "./config";
import { DIFFICULTIES, TOPICS, pingModel, type Difficulty, type Topic } from "./llm";
import { createDemoQuestion, ensureDemoStudentProfile, type SimulationRequest } from "./question";
import { watchSession } from "./student";

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

console.log("[demo-student] Firebase initialised");
console.log(`[demo-student] LLM    : ${config.llmModel} @ ${config.llmBaseUrl} (${config.llmApiType})`);
console.log(`[demo-student] Student: ${config.studentName} (${config.studentUid})`);
console.log(
  `[demo-student] Replies: autoReply=${config.autoReply} delay=${config.replyDelayMs}ms max=${config.maxReplies}`,
);

void (async () => {
  try {
    const reply = await pingModel(config);
    console.log(`[demo-student] LLM reachable — model answered "${reply}"`);
  } catch (err) {
    console.warn(
      `[demo-student] LLM not reachable at ${config.llmBaseUrl}: ${err instanceof Error ? err.message : String(err)}`,
    );
    console.warn(
      config.allowFallbackQuestion
        ? "[demo-student] Simulations will fall back to canned questions until the model is up."
        : "[demo-student] Simulations will fail until the model is up (DEMO_STUDENT_ALLOW_FALLBACK=false).",
    );
  }
})();

// ─── Concurrency limiter ──────────────────────────────────────────────────────

let active = 0;
const waiting: Array<() => void> = [];

function runWhenSlotAvailable(fn: () => Promise<void>): void {
  const run = () => {
    active++;
    fn().finally(() => {
      active--;
      const next = waiting.shift();
      if (next) next();
    });
  };

  if (active < config.maxConcurrent) run();
  else waiting.push(run);
}

// ─── Request parsing ──────────────────────────────────────────────────────────

function parseTopic(raw: unknown): Topic {
  const value = String(raw ?? "").trim().toLowerCase();
  return (TOPICS as readonly string[]).includes(value) ? (value as Topic) : "algebra";
}

function parseDifficulty(raw: unknown): Difficulty {
  const value = String(raw ?? "").trim().toLowerCase();
  return (DIFFICULTIES as string[]).includes(value) ? (value as Difficulty) : "medium";
}

function parseConversationType(raw: unknown): SimulationRequest["conversationType"] {
  const value = String(raw ?? "").trim().toLowerCase();
  return value === "audio" || value === "video" ? value : "text";
}

function parseRequest(requestId: string, data: Record<string, unknown>): SimulationRequest | null {
  const teacherUid = String(data.teacherUid ?? "").trim();
  if (!teacherUid) return null;

  const hint = String(data.hint ?? "").trim();
  return {
    requestId,
    teacherUid,
    topic: parseTopic(data.topic),
    difficulty: parseDifficulty(data.difficulty),
    language: String(data.language ?? "en").trim().toLowerCase() === "he" ? "he" : "en",
    conversationType: parseConversationType(data.conversationType),
    ...(hint ? { hint: hint.slice(0, 200) } : {}),
  };
}

// ─── Request handling ─────────────────────────────────────────────────────────

const db = admin.database();

// Requests written before this process started are stale — the teacher who
// pressed the button is long gone. Anything from the last 60 s still counts,
// which covers a restart in the middle of a demo.
const serviceStartMs = Date.now();
const STARTUP_WINDOW_MS = 60_000;
const handled = new Set<string>();

async function setStatus(
  requestId: string,
  patch: Record<string, unknown>,
): Promise<void> {
  await db.ref(`demoStudent/requests/${requestId}`).update({ ...patch, updatedAt: Date.now() });
}

async function handleRequest(request: SimulationRequest): Promise<void> {
  console.log(
    `[demo-student] request ${request.requestId} teacher=${request.teacherUid} topic=${request.topic} ` +
      `difficulty=${request.difficulty} type=${request.conversationType} lang=${request.language}`,
  );

  try {
    await setStatus(request.requestId, { status: "generating" });
    await ensureDemoStudentProfile(config);

    const created = await createDemoQuestion(config, request);

    await setStatus(request.requestId, {
      status: "dispatched",
      questionId: created.questionId,
      questionText: created.text,
      source: created.source,
    });

    watchSession(config, {
      questionId: created.questionId,
      questionText: created.text,
      topic: request.topic,
      language: request.language,
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[demo-student] request ${request.requestId} failed:`, err);
    await setStatus(request.requestId, { status: "failed", error: message.slice(0, 300) }).catch(() => {});
  }
}

function onRequest(snap: admin.database.DataSnapshot): void {
  const requestId = snap.key;
  if (!requestId || handled.has(requestId)) return;

  const data = (snap.val() ?? {}) as Record<string, unknown>;
  const status = String(data.status ?? "pending").toLowerCase();
  if (status !== "pending") return; // already picked up (by us or a previous run)

  const createdAt = typeof data.createdAt === "number" ? data.createdAt : undefined;
  if (createdAt !== undefined && createdAt < serviceStartMs - STARTUP_WINDOW_MS) {
    console.log(`[demo-student] ignoring stale request ${requestId}`);
    return;
  }

  const request = parseRequest(requestId, data);
  if (!request) {
    console.warn(`[demo-student] ignoring request ${requestId} — no teacherUid`);
    return;
  }

  handled.add(requestId);
  runWhenSlotAvailable(() => handleRequest(request));
}

db.ref("demoStudent/requests").on("child_added", onRequest);
db.ref("demoStudent/requests").on("child_changed", onRequest);

// ─── Graceful shutdown ────────────────────────────────────────────────────────

function shutdown(signal: string): void {
  console.log(`[demo-student] ${signal} received — shutting down`);
  db.goOffline();
  process.exit(0);
}

process.on("SIGINT", () => shutdown("SIGINT"));
process.on("SIGTERM", () => shutdown("SIGTERM"));

console.log("[demo-student] Watching RTDB demoStudent/requests — ready");
