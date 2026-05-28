import { readFileSync } from "fs";

export type LlmApiType = "ollama" | "openai";

export interface Config {
  firebaseServiceAccount: Record<string, unknown> | null; // null = application default creds
  firebaseDatabaseUrl: string;
  llmBaseUrl: string;
  llmModel: string;
  llmApiType: LlmApiType;
  llmTimeoutMs: number;
  answerDelayMs: number;
  maxConcurrent: number;
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

function loadServiceAccount(): Record<string, unknown> | null {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) return null; // fall back to Application Default Credentials

  // If it looks like a file path, read it.
  if (raw.trim().startsWith("/") || raw.trim().startsWith(".")) {
    return JSON.parse(readFileSync(raw.trim(), "utf8")) as Record<string, unknown>;
  }

  // Otherwise treat as an inline JSON string.
  return JSON.parse(raw) as Record<string, unknown>;
}

export function loadConfig(): Config {
  const apiType = process.env.LLM_API_TYPE ?? "ollama";
  if (apiType !== "ollama" && apiType !== "openai") {
    throw new Error(`LLM_API_TYPE must be "ollama" or "openai", got "${apiType}"`);
  }

  return {
    firebaseServiceAccount: loadServiceAccount(),
    firebaseDatabaseUrl: requireEnv("FIREBASE_DATABASE_URL"),
    llmBaseUrl: process.env.LLM_BASE_URL ?? "http://localhost:11434",
    llmModel: process.env.LLM_MODEL ?? "llama3.1",
    llmApiType: apiType,
    llmTimeoutMs: parseInt(process.env.LLM_TIMEOUT_SECONDS ?? "60", 10) * 1000,
    answerDelayMs: Math.max(0, parseInt(process.env.ANSWER_DELAY_MS ?? "1000", 10)),
    maxConcurrent: Math.max(1, parseInt(process.env.MAX_CONCURRENT ?? "2", 10)),
  };
}
