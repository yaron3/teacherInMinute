import { logger } from "firebase-functions";
import { TeacherRecord } from "./types";

// FR-B-002: score = 0.6·(ratingAvg/5) + 0.25·acceptRate + 0.15·recencyFactor
// recencyFactor = exp(-hoursAgo / 24)  →  1.0 when just active, decays to ~0 after 72h

function recencyFactor(lastActiveAt: number): number {
  const hoursAgo = (Date.now() - lastActiveAt) / 3_600_000;
  return Math.exp(-hoursAgo / 24);
}

export function scoreTeacher(teacher: TeacherRecord): number {
  return (
    0.6 * (teacher.ratingAvg / 5) +
    0.25 * teacher.acceptRate +
    0.15 * recencyFactor(teacher.lastActiveAt)
  );
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

// Returns all eligible (online + matching topic) teachers sorted best-first.
// The dispatcher slices the result per wave, skipping alreadyInvited UIDs.
export function rankTeachers(
  teachers: Record<string, TeacherRecord>,
  topic: string,
  exclude: Set<string>
): ScoredTeacher[] {
  const candidates: ScoredTeacher[] = [];
  const normalizedTopic = normalizeSubject(topic);

  // Counted rather than logged one line at a time: this runs on the dispatch
  // path, and a line per rejected teacher meant dozens of Cloud Logging writes
  // per wave that grow with the roster while saying the same thing.
  let offline = 0;
  let topicMismatch = 0;

  for (const [uid, t] of Object.entries(teachers)) {
    if (exclude.has(uid)) continue;
    if (t.status !== "online") {
      offline += 1;
      continue;
    }
    // RTDB can deserialize arrays as {0: "algebra", ...} objects when written by mobile SDKs.
    const subjects: string[] = Array.isArray(t.subjects) ? t.subjects : Object.values(t.subjects ?? {} as Record<string, string>);
    const matches = subjects.some((s) => normalizeSubject(s) === normalizedTopic);
    if (!matches) {
      topicMismatch += 1;
      continue;
    }

    candidates.push({ uid, score: scoreTeacher(t) });
  }

  logger.info(
    `[scoring] ranked topic=${topic} considered=${Object.keys(teachers).length} excluded=${exclude.size} skippedOffline=${offline} skippedTopic=${topicMismatch} eligible=${candidates.length}`
  );

  return candidates.sort((a, b) => b.score - a.score);
}
