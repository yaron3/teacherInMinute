import { Timestamp } from "firebase-admin/firestore";

import { PayoutMethod } from "./payoutMethod";

// ─── Pricing / dispatch constants ───
// Per-minute pricing now lives in Remote Config (see pricing.ts); these
// constants remain only for dispatch sizing and connection-fee fallback.

// A Cloud Functions instance gets CPU in proportion to its memory, and the
// question path is almost entirely cold-start cost: at the 256MiB default,
// loading the module graph took ~4.4s before a single line of a handler ran.
// The extra memory buys ~3.5x the CPU, which is the only lever on cold starts
// short of paying for warm instances. It is close to free — these handlers
// finish in well under a second, and billing is memory x duration, so the
// shorter run largely pays for the bigger box.
export const HOT_PATH = { memory: "1GiB" as const };

export const WAVE_SIZES = [3, 5, 10] as const;
export const WAVE_TIMEOUT_SECONDS = 12;
export const INVITE_EXPIRY_SECONDS = 90;
export const HARD_CAP_MINUTES = 30;

// How long a teacher who accepted waits for the student to actually turn up
// before the lesson is written off. A student's app joins within seconds of
// seeing the acceptance, so this is generous; what it bounds is the case where
// the student is not there at all — their app was killed while searching, or
// they gave up before a teacher with a still-valid invite claimed the question.
// Nobody is charged for such a lesson, and clearing it is what ends the
// teacher's session, since the apps end when the live question node disappears.
export const ABANDONED_LESSON_GRACE_SECONDS = 120;
export const CONNECTION_FEE_CENTS = 50;
export const MIN_BILLABLE_SECONDS = 30;
export const ROUND_UP_SECONDS = 30;

// ─── RTDB — teachers/{uid} ────────────────────────────────────────────────────
//
// Written by the mobile app (goOnline / profile update).
// Dispatcher reads this collection to find eligible online teachers.

export interface TeacherRecord {
  status: "online" | "offline";
  /** What the teacher asked for, as opposed to whether the app is connected.
   *  Written only when they work the availability toggle. */
  availability?: "available" | "dnd";
  subjects: string[];       // ["algebra", "geometry", ...]
  /** 0–5, and absent until a student has actually rated them. Written by the
   *  backend alone — `rateTeacher` mirrors it here and presence stamps it when
   *  a teacher comes online — so it cannot be set by the app that benefits
   *  from it. Absent means unrated, which ./scoring reads as a prior rather
   *  than as zero. */
  ratingAvg?: number;
  /** How many ratings `ratingAvg` is the mean of. */
  ratingCount?: number;
  /** 0–1. Absent until there is anything to measure. */
  acceptRate?: number;
  /** Unix ms. Android writes it; iOS does not, so absence means "unknown",
   *  not "idle". */
  lastActiveAt?: number;
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

export type ConversationType = "text" | "audio" | "video";
export const CONVERSATION_TYPES: ConversationType[] = ["text", "audio", "video"];
export const DEFAULT_CONVERSATION_TYPE: ConversationType = "text";

export interface QuestionDoc {
  studentUid: string;
  studentName?: string;       // snapshot of the student's name at question creation
  studentImageURL?: string;   // snapshot of the student's shared profile image (respects privacy setting)
  topic: string;             // one of the six math sub-topics
  text: string;
  photoUrls: string[];
  voiceMemoUrl?: string;
  conversationType: ConversationType;
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
  /** Written by the demo-student service — a simulated question, not a real one. */
  isDemo?: boolean;
  /** The teacher who asked for the simulation; the only one invited to it. */
  demoTeacherUid?: string;
  /** Simulated without the local AI service — replies come from Remote Config. */
  demoFallback?: boolean;
}

// ─── Firestore — questions/{qid}/invites/{tid} ───────────────────────────────

/** `withdrawn`: the teacher accepted a different question while this invite was
 *  still pending, so the backend took it back and gave the slot to someone else. */
export type InviteResponse = "pending" | "accept" | "decline" | "timeout" | "withdrawn";

export interface DispatchInviteDoc {
  teacherUid: string;
  questionId: string;
  sentAt: Timestamp;
  expiresAt: Timestamp;
  response: InviteResponse;
  wave: number;
  conversationType: ConversationType;
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
  // Currency-aware pricing snapshot — frozen at startLesson so RC changes
  // mid-lesson do not retroactively alter the price.
  currencyCode: string;          // e.g. "ILS", "USD"
  pricePerMinute: number;        // in major units of currencyCode
  teacherShare: number;          // 0–1, e.g. 0.75
  exchangeRateToUsd: number;     // multiplicative rate USD → currencyCode
  totalCents?: number;
  /** Settled at endLesson, in major units of `currencyCode` (not cents). */
  cost?: number;
  /** The teacher's share of `cost`, also in major units. */
  teacherEarnings?: number;
  status: LessonStatus;
  liveKitRoom: string;          // "lesson_<questionId>"
  liveKitTokenExpiry: Timestamp;
  endedBy?: "student" | "teacher" | "system";
  /** Inherited from the question — a lesson taught to the simulated demo student. */
  isDemo?: boolean;
}

// ─── Firestore — pricing/{pricingOptionId} ────────────────────────────────────

export type PlanType = "pay_as_you_go" | "unlimited_week" | "unlimited_month" | "unlimited_year";

export interface PricingDoc {
  name: string;
  priceCents: number;
  currency: string;
  type: PlanType;
  minutes?: number;          // minutes granted on purchase (primary field)
  minutesGranted?: number;   // legacy alias for minutes
  description?: string;
  isHighlighted?: boolean;
  sortOrder?: number;
  active?: boolean;
}

// ─── Firestore — paymentCheckouts/{checkoutId} ───────────────────────────────

export type CheckoutStatus = "created" | "paypal_created" | "completed" | "cancelled";

export interface PaymentCheckoutDoc {
  uid: string;
  packageId: string;
  packageType?: PlanType;
  priceCents: number;
  currency: string;
  minutes: number;
  status: CheckoutStatus;
  createdAt: Timestamp;
  updatedAt?: Timestamp;
  paypalOrderId: string | null;
  approvalUrl?: string;
  completedAt?: Timestamp;
  paypalCaptureId?: string;
  braintreeTransactionId?: string;
  /** Wallet the buyer picked, e.g. "apple_pay", "credit_card". Undefined means default PayPal flow. */
  paymentMethod?: string;
}

// ─── Firestore — users/{uid} ─────────────────────────────────────────────────

export interface UserDoc {
  remainingMinutes: number;  // students: minutes available to use
  totalMinutes: number;      // teachers: cumulative minutes taught
  questions?: string[];
  currency?: string;         // ISO 4217 code; controls pricing for students and display for teachers
  /** A student's vaulted PayPal account (see ./braintree.ts), for one-tap
   *  future purchases without a PayPal login redirect. Unrelated to
   *  `paypalEmail` below, which is a teacher's payout destination. */
  savedPayPal?: {
    paymentMethodToken: string;
    email: string;
    updatedAt: Timestamp;
  };
  paypalEmail?: string;       // teachers: PayPal payout destination
  /** Teachers: where the monthly payout is sent — a bank account, Bit, or
   *  PayPal. Written only by `updateTeacherPayoutMethod`, which validates the
   *  fields required for the chosen type (see ./payoutMethod). */
  payoutMethod?: PayoutMethod & { updatedAt: Timestamp };
}

// ─── Firestore — coupons/{couponId} ──────────────────────────────────────────

export interface CouponDoc {
  price: number;            // price amount (e.g. USD)
  numberOfMinutes: number;
  createdAt: Timestamp;
  activatedAt?: Timestamp;  // set when redeemed
  studentUserId: string;    // the student this coupon is for
  createdBy: string;        // display name of the creator
}

// ─── Firestore — users/{uid}/purchases/{purchaseId} ───────────────────────────

export type PurchaseStatus = "active" | "expired" | "refunded";

export interface PurchaseDoc {
  pricingOptionId: string;
  provider: "paypal" | "braintree";
  amountCents: number;
  currency: string;
  type: PlanType;
  status: PurchaseStatus;
  purchasedAt: Timestamp;
  expiresAt?: Timestamp;
  updatedAt?: Timestamp;
  minutesPurchased?: number;
  minutesRemaining?: number;
  minutesUsed?: number;
}
