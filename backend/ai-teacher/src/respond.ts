import * as admin from "firebase-admin";
import { generateAnswer, classifyIntent, ConversationMessage } from "./llm";
import type { Config } from "./config";

const HANDLED_STATUSES = new Set([
  "accepted", "in_progress", "matched", "connected", "active",
  "completed", "cancelled", "canceled", "expired",
]);

const TERMINAL_STATUSES = new Set([
  "completed", "cancelled", "canceled", "expired", "ended",
]);

const AI_UID = "ai-teacher";
const AI_NAME = "AI Teacher";

const KEEP_ALIVE_MESSAGES = [
  "Still on it, this one needs a bit of thinking!",
  "Bear with me, I want to make sure I explain this clearly.",
  "Almost there, working through the details for you.",
  "Still here, just making sure I get this right!",
];

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ── Helpers ───────────────────────────────────────────────────────────────────

async function sendMessage(
  db: admin.database.Database,
  questionId: string,
  text: string,
): Promise<void> {
  await db.ref(`questions/${questionId}/messages`).push({
    text,
    senderUid: AI_UID,
    senderRole: "teacher",
    createdAt: Date.now(),
    kind: "text",
  });
}

function startKeepAlive(db: admin.database.Database, questionId: string): () => void {
  let index = 0;
  const interval = setInterval(() => {
    const msg = KEEP_ALIVE_MESSAGES[index % KEEP_ALIVE_MESSAGES.length];
    index++;
    sendMessage(db, questionId, msg).catch(() => {});
  }, 45_000);
  return () => clearInterval(interval);
}

function detectSteps(text: string): string[] | null {
  const lines = text.split("\n");
  const stepLineRe = /^(?:\*{0,2}(?:step\s+)?\d+[.):\s]|\*{0,2}step\s+\d+|\#{1,3}\s)/i;
  const steps: string[] = [];
  let current = "";
  for (const line of lines) {
    if (stepLineRe.test(line.trim()) && current.trim()) {
      steps.push(current.trim());
      current = line;
    } else {
      current += (current ? "\n" : "") + line;
    }
  }
  if (current.trim()) steps.push(current.trim());
  return steps.length > 1 ? steps : null;
}

async function prefersStepByStep(text: string, config: Config): Promise<boolean> {
  const prompt =
    `A math teacher offered a student two options: explain step by step, or show the full solution at once.\n` +
    `The student replied: "${text}"\n\n` +
    `Does the student want STEPS or FULL solution?\n` +
    `Reply with exactly one word: "steps" or "full"`;
  try {
    const result = await classifyIntent(config.llmBaseUrl, config.llmModel, config.llmApiType, prompt);
    return result.startsWith("step");
  } catch {
    return text.toLowerCase().includes("step");
  }
}

async function wantsNextStep(text: string, config: Config): Promise<boolean> {
  const prompt =
    `A student is going through a math solution step by step.\n` +
    `After seeing a step the teacher asked: "Ready for the next step, or do you have any questions?"\n` +
    `The student replied: "${text}"\n\n` +
    `Is the student ready to move on, or do they have a question about this step?\n` +
    `Reply with exactly one word: "next" or "question"`;
  try {
    const result = await classifyIntent(config.llmBaseUrl, config.llmModel, config.llmApiType, prompt);
    return result.startsWith("next");
  } catch {
    const t = text.toLowerCase().trim();
    return t === "next" || t === "yes" || t === "ok" || t.includes("continue");
  }
}

// ── Session mode ──────────────────────────────────────────────────────────────

type SessionMode =
  | { kind: "awaitingPreference"; fullAnswer: string; steps: string[] }
  | { kind: "stepByStep"; steps: string[]; nextIndex: number }
  | { kind: "normal" };

// ── Per-question follow-up listener ──────────────────────────────────────────

interface PendingAnswer {
  fullAnswer: string;
  steps: string[] | null;
}

function watchFollowUpMessages(
  questionId: string,
  config: Config,
  initialHistory: ConversationMessage[],
  pending: PendingAnswer | null,
): void {
  const db = admin.database();
  const messagesRef = db.ref(`questions/${questionId}/messages`);
  const questionRef = db.ref(`questions/${questionId}`);

  const startTime = Date.now();
  const history: ConversationMessage[] = [...initialHistory];
  const queue: string[] = [];
  let processing = false;
  let stopped = false;

  let mode: SessionMode = pending
    ? { kind: "awaitingPreference", fullAnswer: pending.fullAnswer, steps: pending.steps ?? [] }
    : { kind: "normal" };

  // Send one step and ask whether to continue or if there are questions.
  async function sendStepWithPrompt(steps: string[], index: number): Promise<void> {
    if (stopped) return;
    await sendMessage(db, questionId, steps[index]);
    await sleep(400);
    if (!stopped) {
      const prompt = index < steps.length - 1
        ? "Ready for the next step, or do you have any questions about this one?"
        : "That covers all the steps! Do you have any questions?";
      await sendMessage(db, questionId, prompt);
    }
  }

  async function callLLM(text: string, slowGreeting: string): Promise<{ thinking: string | null; answer: string }> {
    let stopKA: () => void = () => {};
    const thresholdTimer = setTimeout(() => {
      if (!stopped) {
        sendMessage(db, questionId, slowGreeting).catch(() => {});
        stopKA = startKeepAlive(db, questionId);
      }
    }, 10_000);
    try {
      return await generateAnswer(
        config.llmBaseUrl,
        config.llmModel,
        config.llmApiType,
        "",
        text,
        config.llmTimeoutMs,
        history,
      );
    } finally {
      clearTimeout(thresholdTimer);
      stopKA();
    }
  }

  async function processNext(): Promise<void> {
    if (processing || stopped || queue.length === 0) return;
    processing = true;
    const text = queue.shift()!;

    try {
      // ── Awaiting format preference ────────────────────────────────────────
      if (mode.kind === "awaitingPreference") {
        const { fullAnswer, steps } = mode;
        if (await prefersStepByStep(text, config) && steps.length > 1) {
          mode = { kind: "stepByStep", steps, nextIndex: 0 };
          await sendStepWithPrompt(steps, 0);
        } else {
          mode = { kind: "normal" };
          await sendMessage(db, questionId, fullAnswer);
        }
        history.push({ role: "assistant", content: fullAnswer });
        return;
      }

      // ── Step-by-step mode ─────────────────────────────────────────────────
      if (mode.kind === "stepByStep") {
        const { steps, nextIndex } = mode;

        if (await wantsNextStep(text, config)) {
          const next = nextIndex + 1;
          if (next < steps.length) {
            mode = { kind: "stepByStep", steps, nextIndex: next };
            await sendStepWithPrompt(steps, next);
          } else {
            mode = { kind: "normal" };
            if (!stopped) {
              await sendMessage(db, questionId, "Great, we went through all the steps! Feel free to ask any follow-up questions.");
            }
          }
          return;
        }

        // Student has a question about the current step.
        history.push({ role: "user", content: text });
        const result = await callLLM(text, "Good question! Give me a moment to explain...");
        history.push({ role: "assistant", content: result.answer });

        if (!stopped) {
          if (result.thinking) {
            await sendMessage(db, questionId, `My reasoning:\n${result.thinking}`);
            await sleep(400);
          }
          await sendMessage(db, questionId, result.answer);
          await sleep(400);
          // Re-prompt to continue the step-by-step flow.
          if (!stopped) {
            const prompt = nextIndex < steps.length - 1
              ? "Ready for the next step?"
              : "Any other questions about this?";
            await sendMessage(db, questionId, prompt);
          }
        }
        return;
      }

      // ── Normal follow-up ──────────────────────────────────────────────────
      history.push({ role: "user", content: text });
      const result = await callLLM(text, "Sure, just a second!");
      const { thinking, answer } = result;
      history.push({ role: "assistant", content: answer });

      if (!stopped) {
        if (thinking) {
          await sendMessage(db, questionId, `My reasoning:\n${thinking}`);
          await sleep(400);
        }
        const steps = detectSteps(answer);
        if (steps) {
          mode = { kind: "stepByStep", steps, nextIndex: 0 };
          await sendStepWithPrompt(steps, 0);
        } else {
          await sendMessage(db, questionId, answer);
        }
        console.log(`[ai-teacher] follow-up sent qid=${questionId}`);
      }
    } catch (err) {
      console.error(`[ai-teacher] follow-up error qid=${questionId}:`, err);
      if (mode.kind === "normal") history.pop();
    } finally {
      processing = false;
      void processNext();
    }
  }

  function cleanup(): void {
    if (stopped) return;
    stopped = true;
    messagesRef.off("child_added", onMessage);
    questionRef.off("value", onSession);
    console.log(`[ai-teacher] stopped watching qid=${questionId}`);
  }

  function onMessage(snap: admin.database.DataSnapshot): void {
    const msg = snap.val() as Record<string, unknown>;
    if (String(msg.senderRole ?? "") !== "student") return;
    const createdAt = typeof msg.createdAt === "number" ? msg.createdAt : 0;
    if (createdAt < startTime) return;
    const text = String(msg.text ?? "").trim();
    if (!text) return;
    queue.push(text);
    void processNext();
  }

  function onSession(snap: admin.database.DataSnapshot): void {
    if (!snap.exists()) { cleanup(); return; }
    const status = String((snap.val() as Record<string, unknown>).status ?? "").toLowerCase();
    if (TERMINAL_STATUSES.has(status)) cleanup();
  }

  messagesRef.on("child_added", onMessage);
  questionRef.on("value", onSession);
  console.log(`[ai-teacher] watching follow-ups qid=${questionId} mode=${mode.kind}`);
}

// ── Main entry point ──────────────────────────────────────────────────────────

export async function respondToQuestion(
  questionId: string,
  cachedData: Record<string, unknown>,
  config: Config,
): Promise<void> {
  const db = admin.database();
  const firestore = admin.firestore();

  const rtdbSnap = await db.ref(`questions/${questionId}`).once("value");
  if (!rtdbSnap.exists()) {
    console.log(`[ai-teacher] qid=${questionId} gone from RTDB — skipping`);
    return;
  }

  const question = rtdbSnap.val() as Record<string, unknown>;
  const rtdbStatus = String(question.status ?? "").toLowerCase();
  if (HANDLED_STATUSES.has(rtdbStatus)) {
    console.log(`[ai-teacher] qid=${questionId} already handled status=${rtdbStatus}`);
    return;
  }

  const conversationType = String(question.conversationType ?? question.conversation_type ?? "text");
  if (conversationType !== "text") {
    console.log(`[ai-teacher] qid=${questionId} skipping non-text conversationType=${conversationType}`);
    return;
  }

  const fsQuestionRef = firestore.collection("questions").doc(questionId);
  try {
    await firestore.runTransaction(async (tx) => {
      const doc = await tx.get(fsQuestionRef);
      if (!doc.exists) throw new Error("not found");
      const currentStatus = String(doc.data()?.status ?? "").toLowerCase();
      if (HANDLED_STATUSES.has(currentStatus)) throw new Error(`already handled: ${currentStatus}`);
      tx.update(fsQuestionRef, {
        status: "accepted",
        acceptedByTeacher: AI_UID,
        agoraChannel: `lesson_${questionId}`,
        teacherName: AI_NAME,
        teacherImageURL: "",
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.log(`[ai-teacher] qid=${questionId} claim failed: ${msg}`);
    return;
  }

  const acceptedAt = Date.now();
  await db.ref(`questions/${questionId}`).update({
    status: "accepted",
    teacherName: AI_NAME,
    teacherImageURL: "",
    teacherId: AI_UID,
    acceptedByTeacher: AI_UID,
    acceptedAt,
    updatedAt: acceptedAt,
    liveKitRoom: "",
    liveKitToken: "",
  });
  console.log(`[ai-teacher] accepted qid=${questionId}`);

  await sleep(config.answerDelayMs);

  const topic = String(question.topic ?? cachedData.topic ?? "").trim();
  const questionText = String(question.text ?? cachedData.text ?? "").trim();

  if (!questionText) {
    console.warn(`[ai-teacher] qid=${questionId} no question text — skipping`);
    return;
  }

  console.log(`[ai-teacher] calling LLM qid=${questionId} topic="${topic}" textLength=${questionText.length}`);

  let stopKeepAlive: () => void = () => {};
  const thresholdTimer = setTimeout(() => {
    sendMessage(db, questionId, "Hi! Give me just a moment while I work through this for you.").catch(() => {});
    stopKeepAlive = startKeepAlive(db, questionId);
  }, 10_000);

  let result;
  try {
    result = await generateAnswer(
      config.llmBaseUrl,
      config.llmModel,
      config.llmApiType,
      topic,
      questionText,
      config.llmTimeoutMs,
      [],
    );
  } catch (err) {
    clearTimeout(thresholdTimer);
    stopKeepAlive();
    console.error(`[ai-teacher] LLM error qid=${questionId}:`, err);
    await sendMessage(db, questionId, "I'm having trouble answering right now. Please try again shortly.");
    return;
  }
  clearTimeout(thresholdTimer);
  stopKeepAlive();

  const { thinking, answer } = result;
  console.log(`[ai-teacher] answer generated qid=${questionId} thinking=${!!thinking} answerLength=${answer.length}`);

  if (thinking) {
    await sendMessage(db, questionId, `My reasoning:\n${thinking}`);
    await sleep(400);
  }

  const steps = detectSteps(answer);
  const initialUserMsg = topic
    ? `Math question (topic: ${topic}):\n"${questionText}"`
    : questionText;

  let pending: PendingAnswer | null = null;

  if (steps) {
    await sendMessage(
      db,
      questionId,
      "I can walk you through this step by step, or give you the full solution all at once. Which would you prefer?",
    );
    pending = { fullAnswer: answer, steps };
  } else {
    await sendMessage(db, questionId, answer);
  }

  const initialHistory: ConversationMessage[] = [
    { role: "user", content: initialUserMsg },
    { role: "assistant", content: answer },
  ];

  watchFollowUpMessages(questionId, config, initialHistory, pending);
}
