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

// Returns all eligible (online + matching topic) teachers sorted best-first.
// The dispatcher slices the result per wave, skipping alreadyInvited UIDs.
export function rankTeachers(
  teachers: Record<string, TeacherRecord>,
  topic: string,
  exclude: Set<string>
): ScoredTeacher[] {
  const candidates: ScoredTeacher[] = [];

  for (const [uid, t] of Object.entries(teachers)) {
    if (exclude.has(uid)) continue;
    if (t.status !== "online") continue;
    if (!Array.isArray(t.subjects) || !t.subjects.includes(topic)) continue;

    candidates.push({ uid, score: scoreTeacher(t) });
  }

  return candidates.sort((a, b) => b.score - a.score);
}
