import * as admin from "firebase-admin";

import type { Config } from "./config";
import type { ChatMessage } from "./llm";
import { generateStudentReply } from "./llm";

const ACTIVE_STATUSES = new Set(["accepted", "in_progress", "matched", "connected", "active"]);
const TERMINAL_STATUSES = new Set(["completed", "cancelled", "canceled", "expired", "ended", "unanswered"]);

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export interface StudentSessionParams {
  questionId: string;
  questionText: string;
  topic: string;
  language: string;
}

/**
 * Plays the student side of one demo question: waits for a teacher to accept,
 * then answers every teacher message with a line from the local model, until
 * the student is satisfied, the reply budget runs out, or the session ends.
 */
export function watchSession(config: Config, params: StudentSessionParams): void {
  const db = admin.database();
  const questionRef = db.ref(`questions/${params.questionId}`);
  const messagesRef = questionRef.child("messages");

  const history: ChatMessage[] = [];
  const queue: string[] = [];
  const startedAt = Date.now();

  let listening = false;
  let processing = false;
  let stopped = false;
  let repliesSent = 0;
  let done = false;

  function stop(reason: string): void {
    if (stopped) return;
    stopped = true;
    questionRef.off("value", onQuestion);
    if (listening) messagesRef.off("child_added", onMessage);
    console.log(`[demo-student] session closed qid=${params.questionId} reason=${reason}`);
  }

  async function sendStudentMessage(text: string): Promise<void> {
    await messagesRef.push({
      text,
      senderUid: config.studentUid,
      senderRole: "student",
      createdAt: Date.now(),
      kind: "text",
    });
  }

  async function processNext(): Promise<void> {
    if (processing || stopped || done || queue.length === 0) return;
    processing = true;
    const teacherText = queue.shift()!;

    try {
      history.push({ role: "user", content: teacherText });
      const reply = await generateStudentReply(config, {
        question: params.questionText,
        topic: params.topic,
        language: params.language,
        history,
      });
      history.push({ role: "assistant", content: reply.text });

      if (stopped) return;

      // A small pause so the teacher sees a human-paced answer, not an instant one.
      await sleep(config.replyDelayMs);
      if (stopped) return;

      await sendStudentMessage(reply.text);
      repliesSent++;
      console.log(
        `[demo-student] replied qid=${params.questionId} replies=${repliesSent}/${config.maxReplies} done=${reply.isDone}`,
      );

      if (reply.isDone) {
        done = true;
        stop("student-satisfied");
      } else if (repliesSent >= config.maxReplies) {
        done = true;
        stop("reply-budget-reached");
      }
    } catch (err) {
      console.error(`[demo-student] reply failed qid=${params.questionId}:`, err);
      history.pop(); // drop the unanswered teacher turn so it can be retried later
    } finally {
      processing = false;
      void processNext();
    }
  }

  function onMessage(snap: admin.database.DataSnapshot): void {
    const msg = (snap.val() ?? {}) as Record<string, unknown>;
    if (String(msg.senderRole ?? "") !== "teacher") return;
    if (String(msg.senderUid ?? "") === config.studentUid) return;

    const createdAt = typeof msg.createdAt === "number" ? msg.createdAt : 0;
    if (createdAt > 0 && createdAt < startedAt) return; // pre-existing message

    const text = String(msg.text ?? "").trim();
    if (!text) return;

    queue.push(text);
    void processNext();
  }

  function onQuestion(snap: admin.database.DataSnapshot): void {
    if (!snap.exists()) {
      stop("question-removed");
      return;
    }

    const status = String((snap.val() as Record<string, unknown>).status ?? "").toLowerCase();
    if (TERMINAL_STATUSES.has(status)) {
      stop(`status-${status}`);
      return;
    }

    if (!listening && ACTIVE_STATUSES.has(status)) {
      listening = true;
      messagesRef.on("child_added", onMessage);
      console.log(`[demo-student] teacher accepted qid=${params.questionId} — student is live`);
    }
  }

  if (!config.autoReply) {
    console.log(`[demo-student] auto-reply disabled — not watching qid=${params.questionId}`);
    return;
  }

  questionRef.on("value", onQuestion);
  console.log(`[demo-student] waiting for a teacher to accept qid=${params.questionId}`);
}
