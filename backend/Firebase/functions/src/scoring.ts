import { logger } from "firebase-functions";
import { BUSY_STALE_AFTER_MINUTES, TeacherRecord } from "./types";

// FR-B-002: score = 0.6·(ratingAvg/5) + 0.25·acceptRate + 0.15·recencyFactor
// recencyFactor = exp(-hoursAgo / 24)  →  1.0 when just active, decays to ~0 after 72h
//
// Every term has to survive its value being absent, and each absence means
// something different. A teacher who has never been rated has no `ratingAvg` at
// all — the backend writes one only once a student has given one — and reading
// that as zero would bury every new teacher behind anyone with a single star.
// Reading it as five would do the opposite and let an unrated teacher outrank a
// good one. So the missing value is scored as a prior, and nothing is stored:
// the database still says "no rating".
//
// This used to fall out as NaN rather than anything considered. iOS writes only
// status and subjects, so `ratingAvg`, `acceptRate` and `lastActiveAt` were all
// undefined, the arithmetic produced NaN, and `sort` with a comparator that
// returns NaN leaves the order unspecified — the ranking was not wrong so much
// as absent.

/** What an unrated teacher's rating counts as. Mid-scale: they have not earned
 *  a good average, and have not earned a bad one either. */
const UNRATED_PRIOR = 3.0;

/** No invitations refused on record yet, so nothing is held against them. */
const UNKNOWN_ACCEPT_RATE = 1.0;

/** Only teachers who are online are ranked at all, so an absent `lastActiveAt`
 *  means the app does not write one (iOS), not that the teacher is stale. It is
 *  read as "active now" rather than penalising a whole platform. */
const UNKNOWN_RECENCY = 1.0;

function finite(value: unknown): number | undefined {
  const n = Number(value);
  return Number.isFinite(n) ? n : undefined;
}

/** 0–5, or the prior when this teacher has no ratings yet. */
function ratingOf(teacher: TeacherRecord): number {
  const rating = finite(teacher.ratingAvg);
  if (rating === undefined || rating <= 0) return UNRATED_PRIOR;
  return Math.min(5, rating);
}

function acceptRateOf(teacher: TeacherRecord): number {
  const rate = finite(teacher.acceptRate);
  if (rate === undefined || rate < 0) return UNKNOWN_ACCEPT_RATE;
  return Math.min(1, rate);
}

function recencyFactor(lastActiveAt: unknown): number {
  const activeAt = finite(lastActiveAt);
  if (activeAt === undefined || activeAt <= 0) return UNKNOWN_RECENCY;
  const hoursAgo = (Date.now() - activeAt) / 3_600_000;
  if (hoursAgo <= 0) return 1;
  return Math.exp(-hoursAgo / 24);
}

export function scoreTeacher(teacher: TeacherRecord): number {
  return (
    0.6 * (ratingOf(teacher) / 5) +
    0.25 * acceptRateOf(teacher) +
    0.15 * recencyFactor(teacher.lastActiveAt)
  );
}

/** Whether the teacher is in a session now. A mark older than any session
 *  can last is ignored: its clear was lost, and the teacher is free. */
export function isTeacherBusy(teacher: TeacherRecord, now = Date.now()): boolean {
  const busy = teacher.busy;
  if (!busy || typeof busy.questionId !== "string" || !busy.questionId) return false;
  const since = finite(busy.since);
  if (since === undefined) return true;
  return now - since < BUSY_STALE_AFTER_MINUTES * 60_000;
}

export interface ScoredTeacher {
  uid: string;
  score: number;
}

// Normalize a subject or topic string for matching:
// strips a leading area prefix ("Math: " → ""), lowercases, removes non-alphanumeric.
// "Math: Algebra" → "algebra", "algebra" → "algebra", "Trigonometry" → "trigonometry"
function normalizeSubject(s: string): string {
  const afterColon = s.includes(": ") ? s.split(": ").slice(1).join(": ") : s;
  return afterColon.toLowerCase().replace(/[^a-z0-9]/g, "");
}

// Returns all eligible (online, not in a session, matching topic) teachers sorted best-first.
// The dispatcher slices the result per wave, skipping alreadyInvited UIDs.
export function rankTeachers(
  teachers: Record<string, TeacherRecord>,
  topic: string,
  exclude: Set<string>
): ScoredTeacher[] {
  const candidates: Array<ScoredTeacher & { lastActiveAt: number }> = [];
  const normalizedTopic = normalizeSubject(topic);

  // Counted rather than logged one line at a time: this runs on the dispatch
  // path, and a line per rejected teacher meant dozens of Cloud Logging writes
  // per wave that grow with the roster while saying the same thing.
  let offline = 0;
  let topicMismatch = 0;
  let busy = 0;
  const now = Date.now();

  for (const [uid, t] of Object.entries(teachers)) {
    if (exclude.has(uid)) continue;
    if (t.status !== "online") {
      offline += 1;
      continue;
    }
    if (isTeacherBusy(t, now)) {
      busy += 1;
      continue;
    }
    // RTDB can deserialize arrays as {0: "algebra", ...} objects when written by mobile SDKs.
    const subjects: string[] = Array.isArray(t.subjects) ? t.subjects : Object.values(t.subjects ?? {} as Record<string, string>);
    const matches = subjects.some((s) => normalizeSubject(s) === normalizedTopic);
    if (!matches) {
      topicMismatch += 1;
      continue;
    }

    candidates.push({
      uid,
      score: scoreTeacher(t),
      lastActiveAt: finite(t.lastActiveAt) ?? 0,
    });
  }

  logger.info(
    `[scoring] ranked topic=${topic} considered=${Object.keys(teachers).length} excluded=${exclude.size} skippedOffline=${offline} skippedBusy=${busy} skippedTopic=${topicMismatch} eligible=${candidates.length}`
  );

  // Unrated teachers all score alike, so ties are ordinary rather than rare.
  // Breaking them on recency and then on uid keeps the order defined — left to
  // the sort's own stability it would follow whatever order the keys arrived
  // in, and the same teachers would take wave 1 every time.
  return candidates
    .sort((a, b) => {
      if (b.score !== a.score) return b.score - a.score;
      if (b.lastActiveAt !== a.lastActiveAt) return b.lastActiveAt - a.lastActiveAt;
      return a.uid.localeCompare(b.uid);
    })
    .map(({ uid, score }) => ({ uid, score }));
}
