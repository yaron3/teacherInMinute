// ─── Limits on what a student may submit ─────────────────────────────────────
//
// Tunable from Remote Config so a limit can be changed without a deploy. Each
// getter falls back to the constant below when the key is absent or unreadable,
// so a Remote Config outage never blocks questions.

import { readRcNumber } from "./remoteConfig";

/** Remote Config key holding the longest accepted question text. */
export const QUESTION_MAX_LENGTH_RC_KEY = "question_max_length";

/** Used when the Remote Config key is missing or unreadable. */
export const DEFAULT_QUESTION_MAX_LENGTH = 1024;

/** Longest question text `createQuestion` accepts, in characters, measured
 *  after trimming. */
export async function getQuestionMaxLength(): Promise<number> {
  const fromRc = await readRcNumber(QUESTION_MAX_LENGTH_RC_KEY);
  if (fromRc !== undefined && fromRc >= 1) return Math.floor(fromRc);
  return DEFAULT_QUESTION_MAX_LENGTH;
}

// ─── How often a student may ask ─────────────────────────────────────────────

/** Remote Config keys holding the asking allowances. */
export const QUESTIONS_PER_MINUTE_RC_KEY = "questions_per_minute";
export const QUESTIONS_PER_HOUR_RC_KEY = "questions_per_hour";

export const DEFAULT_QUESTIONS_PER_MINUTE = 2;
export const DEFAULT_QUESTIONS_PER_HOUR = 5;

export interface QuestionRateLimits {
  perMinute: number;
  perHour: number;
}

/** Reads a whole-number allowance, treating a published zero as "no limit" and
 *  anything unusable as the built-in default. */
async function readAllowance(key: string, fallback: number): Promise<number> {
  const fromRc = await readRcNumber(key);
  if (fromRc === undefined || !Number.isFinite(fromRc) || fromRc < 0) return fallback;
  return Math.floor(fromRc);
}

/** How many questions a student may send per minute and per hour. Both come
 *  from one cached template read, so asking for them costs a single fetch. */
export async function getQuestionRateLimits(): Promise<QuestionRateLimits> {
  const [perMinute, perHour] = await Promise.all([
    readAllowance(QUESTIONS_PER_MINUTE_RC_KEY, DEFAULT_QUESTIONS_PER_MINUTE),
    readAllowance(QUESTIONS_PER_HOUR_RC_KEY, DEFAULT_QUESTIONS_PER_HOUR),
  ]);
  return { perMinute, perHour };
}
