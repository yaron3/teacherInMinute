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
