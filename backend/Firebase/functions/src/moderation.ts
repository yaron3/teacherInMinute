// ─── Reporting and blocking teachers ─────────────────────────────────────────
//
// A student can report the teacher of one of their lessons, block them, or
// both (App Store Guideline 1.2: an app with user-generated content needs a
// way to report it and to block the user behind it).
//
//   • reportTeacher   saves `reports/{id}`, emails it to the support
//                     recipients, and optionally blocks the teacher too.
//   • blockTeacher    adds `users/{student}/blockedTeachers/{teacher}`.
//   • unblockTeacher  removes it.
//   • listBlockedTeachers  what Settings → Privacy Controls lists.
//
// The teacher is never taken from the app: every call names a lesson by its
// question id, and the teacher is the one who accepted that question, after
// checking the caller is its student. So a student can only report or block
// someone they actually had a lesson with.
//
// A block takes effect on the next question: createQuestion copies the
// student's blocked teachers onto the question (`blockedTeachers`), and every
// dispatch path leaves them out (see dispatch.ts). acceptInvite refuses them
// as well, for an invite sent before the block.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";

import { sendSupportEmail } from "./contactSupport";
import type { QuestionDoc } from "./types";

const firestore = admin.firestore();

/** What a student can report a teacher for. The app shows its own copy for
 *  each; this is the stored and emailed value. */
export const REPORT_REASONS = [
  "inappropriate",
  "harassment",
  "sexual",
  "off_platform",
  "not_teaching",
  "other",
] as const;
export type ReportReason = (typeof REPORT_REASONS)[number];

/** Long enough for an account of what happened; short enough for an email. */
export const MAX_REPORT_DETAILS_LENGTH = 2000;

/** Bounds a blocked list nobody should come near; also what one read returns. */
const MAX_BLOCKED_TEACHERS = 200;

export interface ReportRequest {
  questionId: string;
  reason: ReportReason;
  details: string;
  block: boolean;
}

/** Validates what the app sent. Throws `invalid-argument` on anything off. */
export function parseReportRequest(data: unknown): ReportRequest {
  const raw = (data ?? {}) as Record<string, unknown>;
  const questionId = typeof raw.questionId === "string" ? raw.questionId.trim() : "";
  if (!questionId) throw new HttpsError("invalid-argument", "questionId is required");

  const reason = raw.reason;
  if (typeof reason !== "string" || !(REPORT_REASONS as readonly string[]).includes(reason)) {
    throw new HttpsError("invalid-argument", `reason must be one of: ${REPORT_REASONS.join(", ")}`);
  }

  const details = typeof raw.details === "string" ? raw.details.trim() : "";
  if (details.length > MAX_REPORT_DETAILS_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `details must be at most ${MAX_REPORT_DETAILS_LENGTH} characters`
    );
  }

  return { questionId, reason: reason as ReportReason, details, block: raw.block === true };
}

/** The email the support recipients get for a report. */
export function buildReportEmail(report: {
  id: string;
  reason: ReportReason;
  details: string;
  blocked: boolean;
  questionId: string;
  reporterUid: string;
  reporterName: string;
  reporterEmail: string;
  teacherUid: string;
  teacherName: string;
}): { subject: string; text: string } {
  const subject = `[Teacher in a Minute] Report: ${report.reason} — ${oneLine(report.teacherName) || report.teacherUid}`;
  const text = [
    "A student reported a teacher. App Review expects a response within 24 hours.",
    "",
    `Reason: ${report.reason}`,
    `Blocked by the student: ${report.blocked ? "yes" : "no"}`,
    "",
    report.details || "(no details given)",
    "",
    "—",
    `Teacher: ${report.teacherName} (${report.teacherUid})`,
    `Student: ${report.reporterName} <${report.reporterEmail}> (${report.reporterUid})`,
    `Lesson (question): ${report.questionId}`,
    `Report ID: ${report.id}`,
  ].join("\n");
  return { subject, text };
}

/** Strips CR/LF so user text cannot inject headers into the subject. */
function oneLine(text: string): string {
  return text.replace(/[\r\n]+/g, " ").trim();
}

/** The teacher of the caller's lesson, after checking it is the caller's. */
async function teacherOfOwnLesson(studentUid: string, questionId: string): Promise<string> {
  const snap = await firestore.collection("questions").doc(questionId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Lesson not found");
  const question = snap.data() as QuestionDoc;
  if (question.studentUid !== studentUid) {
    throw new HttpsError("permission-denied", "Not your lesson");
  }
  const teacherUid = question.acceptedByTeacher;
  if (!teacherUid) {
    throw new HttpsError("failed-precondition", "No teacher joined this lesson");
  }
  return teacherUid;
}

async function displayName(uid: string): Promise<string> {
  const snap = await firestore.collection("users").doc(uid).get();
  const data = snap.data() ?? {};
  return String(data.fullName ?? data.displayName ?? "").trim();
}

function blockedTeachersRef(studentUid: string) {
  return firestore.collection("users").doc(studentUid).collection("blockedTeachers");
}

async function block(studentUid: string, teacherUid: string, questionId: string, teacherName: string) {
  await blockedTeachersRef(studentUid).doc(teacherUid).set({
    teacherUid,
    teacherName,
    questionId,
    blockedAt: FieldValue.serverTimestamp(),
  });
  logger.info(`[moderation] student=${studentUid} blocked teacher=${teacherUid} qid=${questionId}`);
}

/** The teachers a student has blocked, for createQuestion to copy onto the
 *  question. A failed read blocks nobody rather than failing the question. */
export async function blockedTeacherUids(studentUid: string): Promise<string[]> {
  try {
    const snap = await blockedTeachersRef(studentUid).limit(MAX_BLOCKED_TEACHERS).get();
    return snap.docs.map((doc) => doc.id);
  } catch (error) {
    logger.error(`[moderation] could not read blocked teachers for student=${studentUid}`, error);
    return [];
  }
}

export const reportTeacher = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const request = parseReportRequest(req.data);
  const teacherUid = await teacherOfOwnLesson(uid, request.questionId);
  const [teacherName, reporterSnap] = await Promise.all([
    displayName(teacherUid),
    firestore.collection("users").doc(uid).get(),
  ]);
  const reporter = reporterSnap.data() ?? {};
  const reporterName = String(reporter.fullName ?? "").trim();
  const reporterEmail = String(reporter.email ?? req.auth?.token.email ?? "").trim();

  const reportRef = firestore.collection("reports").doc();
  await reportRef.set({
    reporterUid: uid,
    reporterRole: "student",
    reportedUid: teacherUid,
    reportedRole: "teacher",
    reportedName: teacherName,
    questionId: request.questionId,
    reason: request.reason,
    details: request.details,
    blocked: request.block,
    status: "open",
    createdAt: FieldValue.serverTimestamp(),
  });
  logger.info(
    `[moderation] report=${reportRef.id} student=${uid} teacher=${teacherUid} reason=${request.reason} block=${request.block}`
  );

  if (request.block) {
    await block(uid, teacherUid, request.questionId, teacherName);
  }

  // The report is saved either way; a mail failure is logged, not returned, so
  // the student is not told their report failed when it did not.
  const { subject, text } = buildReportEmail({
    id: reportRef.id,
    reason: request.reason,
    details: request.details,
    blocked: request.block,
    questionId: request.questionId,
    reporterUid: uid,
    reporterName,
    reporterEmail,
    teacherUid,
    teacherName,
  });
  await sendSupportEmail(subject, text, reporterEmail).catch((error) => {
    logger.error(`[moderation] could not email report=${reportRef.id}`, error);
  });

  return { reportId: reportRef.id, blocked: request.block };
});

export const blockTeacher = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");
  const questionId = typeof req.data?.questionId === "string" ? req.data.questionId.trim() : "";
  if (!questionId) throw new HttpsError("invalid-argument", "questionId is required");

  const teacherUid = await teacherOfOwnLesson(uid, questionId);
  await block(uid, teacherUid, questionId, await displayName(teacherUid));
  return { blocked: true };
});

export const unblockTeacher = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");
  const teacherUid = typeof req.data?.teacherUid === "string" ? req.data.teacherUid.trim() : "";
  if (!teacherUid) throw new HttpsError("invalid-argument", "teacherUid is required");

  await blockedTeachersRef(uid).doc(teacherUid).delete();
  logger.info(`[moderation] student=${uid} unblocked teacher=${teacherUid}`);
  return { blocked: false };
});

export const listBlockedTeachers = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const snap = await blockedTeachersRef(uid)
    .orderBy("blockedAt", "desc")
    .limit(MAX_BLOCKED_TEACHERS)
    .get();
  return {
    teachers: snap.docs.map((doc) => {
      const data = doc.data();
      return {
        teacherUid: doc.id,
        teacherName: String(data.teacherName ?? ""),
        blockedAtMillis: data.blockedAt?.toMillis?.() ?? 0,
      };
    }),
  };
});
