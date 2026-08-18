import type { Config, LlmApiType } from "./config";

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: string;
}

export type Difficulty = "easy" | "medium" | "hard";
export const DIFFICULTIES: Difficulty[] = ["easy", "medium", "hard"];

// Topics accepted by createQuestion (see functions/src/questions.ts).
export const TOPICS = [
  "algebra",
  "geometry",
  "trigonometry",
  "calculus",
  "statistics",
  "arithmetic",
] as const;
export type Topic = (typeof TOPICS)[number];

const MAX_QUESTION_CHARS = 280;
const MIN_QUESTION_CHARS = 10;

// ─── Response cleanup ────────────────────────────────────────────────────────
// Qwen (and other reasoning-tuned models) wrap chain-of-thought in <think> tags.
// The demo student is a chat participant, so that never reaches the teacher.

function stripThinking(raw: string): string {
  return raw.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
}

function stripWrappingQuotes(text: string): string {
  const trimmed = text.trim();
  const quoted = /^["'“”„«](.*)["'“”»]$/s.exec(trimmed);
  return quoted ? quoted[1].trim() : trimmed;
}

/** Collapses a model answer into one plain-text chat line, without markdown noise. */
function toPlainChatText(raw: string, maxChars: number): string {
  const cleaned = stripThinking(raw)
    // Drop leading list/heading markers the model may add.
    .replace(/^\s*(?:#{1,6}\s*|[-*]\s+|\d+[.)]\s+)/gm, "")
    // Strip bold/italic markers but keep the words.
    .replace(/\*\*(.+?)\*\*/gs, "$1")
    .replace(/(?<!\*)\*(?!\s)(.+?)(?<!\s)\*(?!\*)/gs, "$1")
    .replace(/\r/g, "")
    .replace(/\n{2,}/g, "\n")
    .trim();

  const withoutQuotes = stripWrappingQuotes(cleaned);
  if (withoutQuotes.length <= maxChars) return withoutQuotes;

  // Cut on a sentence boundary when there is one reasonably close to the cap.
  const head = withoutQuotes.slice(0, maxChars);
  const lastStop = Math.max(head.lastIndexOf(". "), head.lastIndexOf("? "), head.lastIndexOf("! "));
  return (lastStop > maxChars * 0.5 ? head.slice(0, lastStop + 1) : head).trim();
}

// ─── Transport ───────────────────────────────────────────────────────────────

interface ChatOptions {
  temperature?: number;
  maxTokens?: number;
  timeoutMs: number;
}

async function chatOllama(
  baseUrl: string,
  model: string,
  messages: ChatMessage[],
  options: ChatOptions,
): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), options.timeoutMs);

  try {
    const res = await fetch(`${baseUrl}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        messages,
        stream: false,
        options: {
          temperature: options.temperature ?? 0.8,
          ...(options.maxTokens ? { num_predict: options.maxTokens } : {}),
        },
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      throw new Error(`Ollama ${res.status}: ${await res.text().catch(() => "(unreadable)")}`);
    }

    const data = (await res.json()) as { message?: { content?: string } };
    const raw = data.message?.content ?? "";
    if (!raw.trim()) throw new Error("Ollama returned an empty response");
    return raw;
  } finally {
    clearTimeout(timer);
  }
}

async function chatOpenAI(
  baseUrl: string,
  model: string,
  messages: ChatMessage[],
  options: ChatOptions,
): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), options.timeoutMs);

  try {
    const res = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        messages,
        temperature: options.temperature ?? 0.8,
        max_tokens: options.maxTokens ?? 512,
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      throw new Error(`LLM API ${res.status}: ${await res.text().catch(() => "(unreadable)")}`);
    }

    const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
    const raw = data.choices?.[0]?.message?.content ?? "";
    if (!raw.trim()) throw new Error("LLM returned an empty response");
    return raw;
  } finally {
    clearTimeout(timer);
  }
}

async function chat(
  baseUrl: string,
  model: string,
  apiType: LlmApiType,
  messages: ChatMessage[],
  options: ChatOptions,
): Promise<string> {
  return apiType === "ollama"
    ? chatOllama(baseUrl, model, messages, options)
    : chatOpenAI(baseUrl, model, messages, options);
}

/** Reachability probe used at startup so a misconfigured LLM fails loudly, early. */
export async function pingModel(config: Config): Promise<string> {
  const raw = await chat(
    config.llmBaseUrl,
    config.llmModel,
    config.llmApiType,
    [{ role: "user", content: "Reply with the single word: ready" }],
    { temperature: 0, maxTokens: 16, timeoutMs: Math.min(config.llmTimeoutMs, 30_000) },
  );
  return stripThinking(raw).slice(0, 40);
}

// ─── Question generation ─────────────────────────────────────────────────────

function languageInstruction(language: string): string {
  return language === "he"
    ? "Write in Hebrew."
    : "Write in English.";
}

const DIFFICULTY_HINTS: Record<Difficulty, string> = {
  easy: "A routine exercise a student can nearly do alone — one concept, small numbers.",
  medium: "A typical homework problem that needs two or three steps.",
  hard: "A problem the student is genuinely stuck on, with a twist or an unfamiliar setup.",
};

export interface QuestionRequest {
  topic: Topic;
  difficulty: Difficulty;
  language: string;
  hint?: string;
}

/**
 * Asks the local model for one realistic student question. Returns plain chat
 * text — no markdown, no solution, short enough for the teacher's invite card.
 */
export async function generateQuestion(config: Config, request: QuestionRequest): Promise<string> {
  const system = [
    "You are simulating a high-school student who is messaging a live math tutor for help.",
    "You write only the student's opening message: the question they are stuck on.",
    "Rules:",
    "- One short message, 1-3 sentences, first person, casual but clear.",
    "- Include the actual exercise (numbers, equation, or figure description) so the tutor can work on it.",
    "- Never include the answer, the solution, or the steps.",
    "- Plain text only: no markdown, no headings, no bullet points, no quotation marks around the message.",
    "- Do not greet by name and do not sign the message.",
  ].join("\n");

  const user = [
    `Topic: ${request.topic}.`,
    `Difficulty: ${request.difficulty}. ${DIFFICULTY_HINTS[request.difficulty]}`,
    request.hint?.trim() ? `The question should be about: ${request.hint.trim()}` : "",
    languageInstruction(request.language),
    "Write the student's message now.",
  ]
    .filter(Boolean)
    .join("\n");

  const raw = await chat(
    config.llmBaseUrl,
    config.llmModel,
    config.llmApiType,
    [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
    { temperature: 0.9, maxTokens: 300, timeoutMs: config.llmTimeoutMs },
  );

  const text = toPlainChatText(raw, MAX_QUESTION_CHARS);
  if (text.length < MIN_QUESTION_CHARS) {
    throw new Error(`Model returned a too-short question (${text.length} chars)`);
  }
  return text;
}

// ─── Student replies ─────────────────────────────────────────────────────────

const REPLY_MAX_CHARS = 220;
const DONE_MARKER = "<done>";

export interface StudentReply {
  text: string;
  /** True when the student considers the lesson finished and should stop replying. */
  isDone: boolean;
}

/**
 * Generates the demo student's next chat message given what the teacher said.
 * `history` is the conversation so far, oldest first, from the student's point
 * of view (`assistant` = the demo student, `user` = the teacher).
 */
export async function generateStudentReply(
  config: Config,
  params: { question: string; topic: string; language: string; history: ChatMessage[] },
): Promise<StudentReply> {
  const system = [
    "You are role-playing a high-school student in a live one-on-one tutoring chat.",
    `You asked your tutor this question: "${params.question}" (topic: ${params.topic}).`,
    "Stay in character as the student for the whole conversation.",
    "Rules:",
    "- Reply with one short chat message, 1-2 sentences.",
    "- React to what the tutor just said: answer their question, try the step they suggested, or say what confuses you.",
    "- You are a learner: do not produce the full solution, and it is fine to make a small mistake or ask why.",
    "- Plain text only, no markdown, no quotation marks around the message.",
    `- When the explanation has fully answered you, thank the tutor and end your message with ${DONE_MARKER}`,
    languageInstruction(params.language),
  ].join("\n");

  const raw = await chat(
    config.llmBaseUrl,
    config.llmModel,
    config.llmApiType,
    [{ role: "system", content: system }, ...params.history],
    { temperature: 0.8, maxTokens: 240, timeoutMs: config.llmTimeoutMs },
  );

  const cleaned = stripThinking(raw);
  const isDone = cleaned.toLowerCase().includes(DONE_MARKER);
  const withoutMarker = cleaned.replace(new RegExp(DONE_MARKER, "gi"), " ");
  const text = toPlainChatText(withoutMarker, REPLY_MAX_CHARS);

  if (!text) throw new Error("Model returned an empty student reply");
  return { text, isDone };
}
