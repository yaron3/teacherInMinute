// ─── Daily summary email ─────────────────────────────────────────────────────
//
// Sunday to Friday at 09:00 Israel time, emails the last 24 hours to the
// recipients set in the admin console (Daily Report page):
//
//   • new accounts, and accounts that finished registration (have an email);
//   • lessons that ended, and their average length;
//   • teachers who were available, and their average time online;
//   • questions asked, with and without demo users and simulated questions.
//
// Settings live in `adminSettings/dailyReport` (admin-only: the collection
// falls under the catch-all deny in firestore.rules). Until the console saves
// them, the report goes to DEFAULT_RECIPIENTS.
//
// Mail goes out over SMTP with the SMTP_* env vars (see ./mailer). Without
// SMTP_HOST the report is logged instead of sent.
//
// Demo users (see ./demoUsers) are left out of every figure, except the one
// question count that says it includes them.

import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { Timestamp } from "firebase-admin/firestore";

import { readDemoUserUids } from "./demoUsers";
import { sendMail } from "./mailer";
import { summarizeTeacherAvailability, TeacherAvailability } from "./presenceHistory";

export const ADMIN_SETTINGS_COLLECTION = "adminSettings";
export const DAILY_REPORT_DOC = "dailyReport";
/**
 * When each account was first seen with an email, one document per uid.
 * Registration has no timestamp of its own — an anonymous account keeps its
 * uid and creation time when the email is linked — so each run stamps the
 * accounts that have gained one since the last.
 */
export const REGISTRATIONS_COLLECTION = "reportRegistrations";

export const DEFAULT_RECIPIENTS = ["yaronj3@gmail.com"];
export const RECIPIENTS_MAX = 20;
export const REPORT_TIME_ZONE = "Asia/Jerusalem";

const DAY_MS = 24 * 3600 * 1000;

export interface DailyReportSettings {
  enabled: boolean;
  recipients: string[];
}

export interface DailyReport {
  fromMs: number;
  toMs: number;
  users: { created: number; registered: number };
  lessons: { count: number; avgSeconds: number | null };
  teachers: TeacherAvailability;
  questions: { all: number; real: number };
}

// ─── Settings ────────────────────────────────────────────────────────────────

function settingsRef() {
  return admin.firestore().collection(ADMIN_SETTINGS_COLLECTION).doc(DAILY_REPORT_DOC);
}

/** Addresses from a list or a comma/newline-separated string, deduplicated. */
export function parseRecipients(value: unknown): string[] {
  const parts = Array.isArray(value) ? value : String(value ?? "").split(/[\s,;]+/);
  const emails = parts
    .map((p) => String(p ?? "").trim().toLowerCase())
    .filter((p) => p.length > 0);
  return [...new Set(emails)];
}

export function isPlausibleEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value);
}

export async function readDailyReportSettings(): Promise<DailyReportSettings & { lastSentAtMs: number | null }> {
  const data = (await settingsRef().get()).data() ?? {};
  const recipients = parseRecipients(data.recipients).filter(isPlausibleEmail);
  const lastSentAt = data.lastSentAt as Timestamp | undefined;
  return {
    enabled: data.enabled !== false,
    recipients: data.recipients === undefined ? DEFAULT_RECIPIENTS : recipients,
    lastSentAtMs: lastSentAt?.toMillis?.() ?? null,
  };
}

export async function writeDailyReportSettings(settings: DailyReportSettings, by: string | undefined): Promise<void> {
  await settingsRef().set(
    { enabled: settings.enabled, recipients: settings.recipients, updatedAt: Timestamp.now(), updatedBy: by ?? null },
    { merge: true }
  );
}

// ─── Figures ─────────────────────────────────────────────────────────────────

function dateToMs(value: unknown): number | null {
  if (value instanceof Timestamp) return value.toMillis();
  if (typeof value === "number") return value < 1e12 ? value * 1000 : value;
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  const obj = value as { toMillis?: () => number } | null | undefined;
  return typeof obj?.toMillis === "function" ? obj.toMillis() : null;
}

/**
 * Accounts created in the window, and accounts that finished registration in
 * it. Stamps every account with an email that has no registration record yet.
 * On the very first run every such account is old news, so it is stamped with
 * its creation time and counted only if that falls in the window.
 */
async function summarizeUsers(fromMs: number, toMs: number, demoUids: Set<string>, firstRun: boolean) {
  const firestore = admin.firestore();
  const accounts: admin.auth.UserRecord[] = [];
  let pageToken: string | undefined;
  do {
    const page = await admin.auth().listUsers(1000, pageToken);
    accounts.push(...page.users);
    pageToken = page.pageToken;
  } while (pageToken);

  const real = accounts.filter((u) => !demoUids.has(u.uid));
  const created = real.filter((u) => {
    const ms = Date.parse(u.metadata.creationTime);
    return ms >= fromMs && ms < toMs;
  }).length;

  const withEmail = real.filter((u) => Boolean(u.email));
  let registered = 0;
  for (let i = 0; i < withEmail.length; i += 300) {
    const chunk = withEmail.slice(i, i + 300);
    const refs = chunk.map((u) => firestore.collection(REGISTRATIONS_COLLECTION).doc(u.uid));
    const snaps = await firestore.getAll(...refs);
    const batch = firestore.batch();
    let writes = 0;
    snaps.forEach((snap, index) => {
      let registeredAtMs = dateToMs(snap.data()?.registeredAt);
      if (registeredAtMs === null) {
        const createdMs = Date.parse(chunk[index].metadata.creationTime);
        registeredAtMs = firstRun && Number.isFinite(createdMs) ? createdMs : toMs;
        batch.set(refs[index], { registeredAt: Timestamp.fromMillis(registeredAtMs) });
        writes += 1;
      }
      if (registeredAtMs >= fromMs && registeredAtMs <= toMs) registered += 1;
    });
    if (writes > 0) await batch.commit();
  }

  return { created, registered };
}

/** Lessons that ended in the window. Length is the unrounded time talked. */
async function summarizeLessons(fromMs: number, toMs: number, demoUids: Set<string>) {
  const snap = await admin
    .firestore()
    .collection("lessons")
    .where("endedAt", ">=", Timestamp.fromMillis(fromMs))
    .where("endedAt", "<", Timestamp.fromMillis(toMs))
    .get();

  let count = 0;
  let totalSeconds = 0;
  for (const doc of snap.docs) {
    const l = doc.data();
    if (l.status !== "completed") continue;
    if (demoUids.has(String(l.studentUid ?? "")) || demoUids.has(String(l.teacherUid ?? ""))) continue;
    const seconds = Number(l.lessonSeconds ?? l.durationSeconds ?? l.billedSeconds);
    count += 1;
    if (Number.isFinite(seconds) && seconds > 0) totalSeconds += seconds;
  }
  return { count, avgSeconds: count > 0 ? Math.round(totalSeconds / count) : null };
}

/** Questions asked in the window: all of them, and those with no demo user
 *  on either side that the demo-student service did not simulate. */
async function summarizeQuestions(fromMs: number, toMs: number, demoUids: Set<string>) {
  const snap = await admin
    .firestore()
    .collection("questions")
    .where("createdAt", ">=", Timestamp.fromMillis(fromMs))
    .where("createdAt", "<", Timestamp.fromMillis(toMs))
    .get();

  const real = snap.docs.filter((d) => {
    const q = d.data();
    return (
      q.isDemo !== true &&
      !demoUids.has(String(q.studentUid ?? "")) &&
      !demoUids.has(String(q.acceptedByTeacher ?? ""))
    );
  });
  return { all: snap.size, real: real.length };
}

export async function buildDailyReport(toMs: number, firstRun = false): Promise<DailyReport> {
  const fromMs = toMs - DAY_MS;
  const demoUids = await readDemoUserUids();
  const [users, lessons, teachers, questions] = await Promise.all([
    summarizeUsers(fromMs, toMs, demoUids, firstRun),
    summarizeLessons(fromMs, toMs, demoUids),
    summarizeTeacherAvailability(fromMs, toMs),
    summarizeQuestions(fromMs, toMs, demoUids),
  ]);
  return { fromMs, toMs, users, lessons, teachers, questions };
}

// ─── Email ───────────────────────────────────────────────────────────────────

export function formatMinutes(seconds: number | null): string {
  if (seconds === null) return "—";
  const total = Math.round(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  if (h > 0) return `${h}h ${m}m`;
  return m > 0 ? `${m}m ${s}s` : `${s}s`;
}

function israelTime(ms: number): string {
  return new Date(ms).toLocaleString("en-GB", {
    timeZone: REPORT_TIME_ZONE,
    weekday: "short",
    day: "numeric",
    month: "short",
    hour: "2-digit",
    minute: "2-digit",
  });
}

export function formatDailyReportEmail(report: DailyReport): { subject: string; text: string; html: string } {
  const { users, lessons, teachers, questions } = report;
  const rows: Array<[string, string]> = [
    ["New users", String(users.created)],
    ["Finished registration (added email)", String(users.registered)],
    ["Sessions", String(lessons.count)],
    ["Average session length", formatMinutes(lessons.avgSeconds)],
    ["Teachers available", String(teachers.distinctTeachers)],
    ["Average time available per teacher", formatMinutes(teachers.avgSecondsPerTeacher)],
    ["Questions asked (excluding demo)", String(questions.real)],
    ["Questions asked (including demo)", String(questions.all)],
  ];

  const window = `${israelTime(report.fromMs)} – ${israelTime(report.toMs)} (Israel time)`;
  const coverage =
    teachers.hoursCovered < 24
      ? `Teacher availability covers ${teachers.hoursCovered} of 24 hours with presence samples.`
      : "";
  const footer = "Demo users are left out of every figure except the one marked “including demo”.";

  const subject = `[Teacher in a Minute] Daily summary — ${israelTime(report.toMs).split(",")[0]}`;
  const text = [
    `Last 24 hours: ${window}`,
    "",
    ...rows.map(([label, value]) => `${label}: ${value}`),
    "",
    coverage,
    footer,
  ]
    .filter((line, i, all) => line !== "" || all[i - 1] !== "")
    .join("\n");

  const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const html = `<div style="font-family:-apple-system,Segoe UI,Arial,sans-serif;font-size:14px;color:#222">
<p style="margin:0 0 12px">Last 24 hours: ${esc(window)}</p>
<table cellpadding="6" style="border-collapse:collapse">
${rows
  .map(
    ([label, value]) =>
      `<tr><td style="border-bottom:1px solid #eee">${esc(label)}</td><td style="border-bottom:1px solid #eee;font-weight:600;text-align:right">${esc(value)}</td></tr>`
  )
  .join("\n")}
</table>
${coverage ? `<p style="color:#777;margin:12px 0 0">${esc(coverage)}</p>` : ""}
<p style="color:#777;margin:12px 0 0">${esc(footer)}</p>
</div>`;

  return { subject, text, html };
}

// ─── Sending ─────────────────────────────────────────────────────────────────

/**
 * Builds the report for the 24 hours up to `nowMs` and emails it to
 * `recipients` (the saved ones when omitted). Resolves to the report and
 * whether SMTP actually sent it.
 */
export async function sendDailyReport(
  nowMs: number,
  recipients?: string[]
): Promise<{ report: DailyReport; sent: boolean; recipients: string[] }> {
  const settingsSnap = await settingsRef().get();
  const firstRun = !settingsSnap.data()?.lastRunAt;
  const to = recipients ?? (await readDailyReportSettings()).recipients;

  const report = await buildDailyReport(nowMs, firstRun);
  await settingsRef().set({ lastRunAt: Timestamp.fromMillis(nowMs) }, { merge: true });

  if (to.length === 0) {
    logger.warn("[dailyReport] no recipients; not sending");
    return { report, sent: false, recipients: to };
  }

  const sent = await sendMail({ to, ...formatDailyReportEmail(report) });
  if (sent) {
    await settingsRef().set({ lastSentAt: Timestamp.fromMillis(nowMs) }, { merge: true });
    logger.info(`[dailyReport] sent to ${to.length} recipient(s)`);
  }
  return { report, sent: Boolean(sent), recipients: to };
}

/** Sunday to Friday, 09:00 Israel time. */
export const dailySummaryReport = onSchedule(
  { schedule: "0 9 * * 0-5", timeZone: REPORT_TIME_ZONE, timeoutSeconds: 300 },
  async () => {
    const settings = await readDailyReportSettings();
    if (!settings.enabled) {
      logger.info("[dailyReport] disabled in the admin console; skipping");
      return;
    }
    await sendDailyReport(Date.now(), settings.recipients);
  }
);
