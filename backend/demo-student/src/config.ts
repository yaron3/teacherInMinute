import { existsSync, readFileSync } from "fs";
import { resolve } from "path";

export type LlmApiType = "ollama" | "openai";

export interface Config {
  firebaseServiceAccount: Record<string, unknown> | null; // null = application default creds
  firebaseDatabaseUrl: string;
  llmBaseUrl: string;
  llmModel: string;
  llmApiType: LlmApiType;
  llmTimeoutMs: number;
  studentUid: string;
  studentName: string;
  studentImageUrl: string;
  studentMinutes: number;
  studentCurrency: string;
  autoReply: boolean;
  replyDelayMs: number;
  maxReplies: number;
  allowFallbackQuestion: boolean;
  requestMaxAgeMs: number;
  maxConcurrent: number;
}

function requireEnv(name: string): string {
  const v = process.env[name];
  if (v) return v;

  // Nearly always the same cause: `.env` was never created from the example.
  const envPath = resolve(process.cwd(), ".env");
  if (!existsSync(envPath)) {
    throw new Error(
      `No .env file found at ${envPath}.\n` +
        `Create one first:  cp .env.example .env\n` +
        `then set FIREBASE_SERVICE_ACCOUNT to your service-account JSON.`,
    );
  }
  throw new Error(`Missing required env var: ${name} (add it to ${envPath})`);
}

function boolEnv(name: string, fallback: boolean): boolean {
  const raw = process.env[name];
  if (raw === undefined || raw.trim() === "") return fallback;
  return ["1", "true", "yes", "on"].includes(raw.trim().toLowerCase());
}

function loadServiceAccount(): Record<string, unknown> | null {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) return null; // fall back to Application Default Credentials

  // If it looks like a file path, read it.
  const trimmed = raw.trim();
  if (trimmed.startsWith("/") || trimmed.startsWith(".")) {
    if (!existsSync(trimmed)) {
      throw new Error(
        `FIREBASE_SERVICE_ACCOUNT points at ${trimmed}, which does not exist.\n` +
          `Set it to the service-account JSON you downloaded from the Firebase console\n` +
          `(Project settings -> Service accounts -> Generate new private key), or remove\n` +
          `the line entirely to use Application Default Credentials.`,
      );
    }
    return JSON.parse(readFileSync(trimmed, "utf8")) as Record<string, unknown>;
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
    llmModel: process.env.LLM_MODEL ?? "qwen2.5:7b",
    llmApiType: apiType,
    llmTimeoutMs: parseInt(process.env.LLM_TIMEOUT_SECONDS ?? "60", 10) * 1000,
    studentUid: process.env.DEMO_STUDENT_UID ?? "demo-student",
    studentName: process.env.DEMO_STUDENT_NAME ?? "Demo Student",
    studentImageUrl: process.env.DEMO_STUDENT_IMAGE_URL ?? "",
    studentMinutes: Math.max(0, parseInt(process.env.DEMO_STUDENT_MINUTES ?? "120", 10)),
    studentCurrency: process.env.DEMO_STUDENT_CURRENCY ?? "ILS",
    autoReply: boolEnv("DEMO_STUDENT_AUTO_REPLY", true),
    replyDelayMs: Math.max(0, parseInt(process.env.DEMO_STUDENT_REPLY_DELAY_MS ?? "2500", 10)),
    maxReplies: Math.max(1, parseInt(process.env.DEMO_STUDENT_MAX_REPLIES ?? "25", 10)),
    allowFallbackQuestion: boolEnv("DEMO_STUDENT_ALLOW_FALLBACK", true),
    requestMaxAgeMs:
      Math.max(60, parseInt(process.env.DEMO_STUDENT_REQUEST_MAX_AGE_SECONDS ?? "600", 10)) * 1000,
    maxConcurrent: Math.max(1, parseInt(process.env.MAX_CONCURRENT ?? "2", 10)),
  };
}
