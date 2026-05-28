import type { LlmApiType } from "./config";

const SYSTEM_PROMPT = `You are a calm, patient, and accurate high school math teacher.
Your role is to help students understand and solve math problems step by step.

Rules:
- Explain your reasoning clearly, one step at a time.
- Use simple language appropriate for high school students.
- Remember the conversation — refer to earlier messages when it helps.
- If the student made a conceptual error, gently point it out and correct it.
- If the question is completely unrelated to mathematics, respond with exactly:
  "I'm sorry, I can only help with math questions. Please try rephrasing your question."
- Keep your answer focused and do not add unnecessary padding.`.trim();

export interface ConversationMessage {
  role: "user" | "assistant";
  content: string;
}

export interface LLMResult {
  thinking: string | null; // chain-of-thought from <think>…</think>, if present
  answer: string;          // clean final answer
}

// Extract <think>…</think> block and return it separately from the answer.
function parseResponse(raw: string): LLMResult {
  const match = raw.match(/<think>([\s\S]*?)<\/think>/i);
  if (!match) return { thinking: null, answer: raw.trim() };
  const thinking = match[1].trim() || null;
  const answer = raw.replace(/<think>[\s\S]*?<\/think>/gi, "").trim();
  return { thinking, answer };
}

// ─── Ollama /api/chat ─────────────────────────────────────────────────────────

async function queryOllama(
  baseUrl: string,
  model: string,
  topic: string,
  questionText: string,
  timeoutMs: number,
  history: ConversationMessage[],
): Promise<LLMResult> {
  const topicNote = topic ? ` (topic: ${topic})` : "";
  const userContent = history.length === 0
    ? `Math question${topicNote}:\n"${questionText}"`
    : questionText;

  const messages = [
    { role: "system", content: SYSTEM_PROMPT },
    ...history,
    { role: "user", content: userContent },
  ];

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(`${baseUrl}/api/chat`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ model, messages, stream: false }),
      signal: controller.signal,
    });

    if (!res.ok) {
      throw new Error(`Ollama ${res.status}: ${await res.text().catch(() => "(unreadable)")}`);
    }

    const data = (await res.json()) as { message?: { content?: string } };
    const raw = data.message?.content ?? "";
    if (!raw.trim()) throw new Error("Ollama returned an empty response");
    return parseResponse(raw);
  } finally {
    clearTimeout(timer);
  }
}

// ─── OpenAI-compatible /v1/chat/completions ───────────────────────────────────

async function queryOpenAI(
  baseUrl: string,
  model: string,
  topic: string,
  questionText: string,
  timeoutMs: number,
  history: ConversationMessage[],
): Promise<LLMResult> {
  const topicNote = topic ? ` (topic: ${topic})` : "";
  const userContent = history.length === 0
    ? `Math question${topicNote}:\n"${questionText}"`
    : questionText;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    const res = await fetch(`${baseUrl}/v1/chat/completions`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          ...history,
          { role: "user", content: userContent },
        ],
        temperature: 0.3,
        max_tokens: 1024,
      }),
      signal: controller.signal,
    });

    if (!res.ok) {
      throw new Error(`LLM API ${res.status}: ${await res.text().catch(() => "(unreadable)")}`);
    }

    const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
    const raw = data.choices?.[0]?.message?.content ?? "";
    if (!raw.trim()) throw new Error("LLM returned an empty response");
    return parseResponse(raw);
  } finally {
    clearTimeout(timer);
  }
}

// ─── Intent classifier ───────────────────────────────────────────────────────
// Sends a tiny classification prompt and returns the model's one-word response.
// Used for "next step vs question" and "step-by-step vs all at once" decisions.

export async function classifyIntent(
  baseUrl: string,
  model: string,
  apiType: LlmApiType,
  prompt: string,
  timeoutMs = 20_000,
): Promise<string> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);

  try {
    if (apiType === "ollama") {
      const res = await fetch(`${baseUrl}/api/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model,
          messages: [{ role: "user", content: prompt }],
          stream: false,
        }),
        signal: controller.signal,
      });
      if (!res.ok) throw new Error(`Ollama ${res.status}`);
      const data = (await res.json()) as { message?: { content?: string } };
      return parseResponse(data.message?.content ?? "").answer.toLowerCase().trim();
    } else {
      const res = await fetch(`${baseUrl}/v1/chat/completions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model,
          messages: [{ role: "user", content: prompt }],
          max_tokens: 10,
          temperature: 0,
        }),
        signal: controller.signal,
      });
      if (!res.ok) throw new Error(`LLM ${res.status}`);
      const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
      return parseResponse(data.choices?.[0]?.message?.content ?? "").answer.toLowerCase().trim();
    }
  } finally {
    clearTimeout(timer);
  }
}

// ─── Public entry point ───────────────────────────────────────────────────────

export async function generateAnswer(
  baseUrl: string,
  model: string,
  apiType: LlmApiType,
  topic: string,
  questionText: string,
  timeoutMs: number,
  history: ConversationMessage[] = [],
): Promise<LLMResult> {
  return apiType === "ollama"
    ? queryOllama(baseUrl, model, topic, questionText, timeoutMs, history)
    : queryOpenAI(baseUrl, model, topic, questionText, timeoutMs, history);
}
