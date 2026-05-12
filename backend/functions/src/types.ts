import { Timestamp } from "firebase-admin/firestore";

// ─── Pricing / dispatch constants (pilot hard-coded; move to Remote Config later) ───

export const WAVE_SIZES = [3, 5, 10] as const;
export const WAVE_TIMEOUT_SECONDS = 12;
export const HARD_CAP_MINUTES = 30;
export const BASE_RATE_PER_MIN_CENTS = 99;
export const CONNECTION_FEE_CENTS = 50;
export const MIN_BILLABLE_SECONDS = 30;
export const ROUND_UP_SECONDS = 30;

// ─── RTDB — teachers/{uid} ────────────────────────────────────────────────────
//
// Written by the mobile app (goOnline / profile update).
// Dispatcher reads this collection to find eligible online teachers.

export interface TeacherRecord {
  status: "online" | "offline";
  subjects: string[];       // ["algebra", "geometry", ...]
  ratingAvg: number;        // 0–5,  default 3.0 for new teachers
  acceptRate: number;       // 0–1,  default 1.0 for new teachers
  lastActiveAt: number;     // Unix ms
  fcmToken?: string;        // registered by the app on login
  displayName: string;
  photoUrl?: string;
}

// ─── Firestore — questions/{qid} ─────────────────────────────────────────────

export type QuestionStatus =
  | "searching"
  | "accepted"
  | "in_progress"
  | "completed"
  | "cancelled"
  | "unanswered";

export interface QuestionDoc {
  studentUid: string;
  topic: string;             // one of the six math sub-topics
  text: string;
  photoUrls: string[];
  voiceMemoUrl?: string;
  status: QuestionStatus;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  dispatchWave: number;      // wave currently being evaluated (1 | 2 | 3)
  alreadyInvited: string[];  // all teacher UIDs invited across all waves
  acceptedByTeacher?: string;
  acceptedAt?: Timestamp;
  startedAt?: Timestamp;
  endedAt?: Timestamp;
  billedSeconds?: number;
  totalCents?: number;
  endedBy?: "student" | "teacher" | "system";
  lessonId?: string;
}

// ─── Firestore — questions/{qid}/invites/{tid} ───────────────────────────────

export type InviteResponse = "pending" | "accept" | "decline" | "timeout";

export interface DispatchInviteDoc {
  teacherUid: string;
  questionId: string;
  sentAt: Timestamp;
  expiresAt: Timestamp;
  response: InviteResponse;
  wave: number;
}

// ─── Firestore — lessons/{lid} ───────────────────────────────────────────────

export type LessonStatus = "in_progress" | "completed";

export interface LessonDoc {
  questionId: string;
  studentUid: string;
  teacherUid: string;
  startedAt: Timestamp;
  hardCapAt: Timestamp;         // startedAt + 30 min — Cloud Task fires here
  endedAt?: Timestamp;
  billedSeconds?: number;
  baseRatePerMinCents: number;
  connectionFeeCents: number;
  totalCents?: number;
  status: LessonStatus;
  liveKitRoom: string;          // "lesson_<questionId>"
  liveKitTokenExpiry: Timestamp;
  endedBy?: "student" | "teacher" | "system";
}
