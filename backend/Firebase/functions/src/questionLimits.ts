// ─── Limits on what a student may submit ─────────────────────────────────────
//
// Tunable from Remote Config so a limit can be changed without a deploy. Each
// getter falls back to the constant below when the key is absent or unreadable,
// so a Remote Config outage never blocks questions.

import { readRcNumber } from "./remoteConfig";
import { INVITE_EXPIRY_SECONDS } from "./types";

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

// ─── How long a question searches ────────────────────────────────────────────

/** Remote Config key holding how long a question is offered to teachers before
 *  the search gives up, in seconds. The app reads it too, for a backend that
 *  does not return it. */
export const SEARCH_TIMEOUT_RC_KEY = "question_search_timeout_seconds";

export const DEFAULT_SEARCH_TIMEOUT_SECONDS = INVITE_EXPIRY_SECONDS;

/** A published value is held to these: long enough for the waves to go out,
 *  short enough that the student's LiveKit token, minted as they ask and good
 *  for an hour, still covers the search and a whole lesson. */
export const MIN_SEARCH_TIMEOUT_SECONDS = 30;
export const MAX_SEARCH_TIMEOUT_SECONDS = 600;

/** How long a new question searches, in whole seconds. */
export async function getSearchTimeoutSeconds(): Promise<number> {
  const fromRc = await readRcNumber(SEARCH_TIMEOUT_RC_KEY);
  if (fromRc === undefined || !Number.isFinite(fromRc)) return DEFAULT_SEARCH_TIMEOUT_SECONDS;
  return Math.min(MAX_SEARCH_TIMEOUT_SECONDS, Math.max(MIN_SEARCH_TIMEOUT_SECONDS, Math.round(fromRc)));
}
