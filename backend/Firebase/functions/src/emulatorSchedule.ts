/**
 * Makes delayed tasks wait on the local emulators, as they do in production.
 *
 * Every timed step of a question and a lesson is a Cloud Task enqueued with a
 * delay: the next wave after 12 s, the search timeout after 90 s, the
 * abandoned-lesson check after 2 min. The Cloud Tasks emulator ignores the
 * delay and runs each task the moment it is enqueued, so on the emulators a
 * question is written off as unanswered within a second of being asked and
 * nothing that depends on timing can be tested.
 *
 * A handler calls `deferredInEmulator` first. Outside the emulator it returns
 * false at once and nothing changes. On the emulator, a task that arrived
 * before its scheduled time waits for it, at most MAX_WAIT_MS per run so the
 * handler stays inside its own timeout, and if still early is enqueued again
 * for the same time and the run ends.
 */
import { getFunctions } from "firebase-admin/functions";
import { logger } from "firebase-functions";

const MAX_WAIT_MS = 45_000;

/**
 * When the task was meant to run, in Unix ms, from the X-CloudTasks-TaskETA
 * header: seconds since the epoch in production, an ISO date or milliseconds
 * from the emulator. Undefined if unreadable.
 */
export function scheduledTimeMillis(scheduledTime: string | undefined): number | undefined {
  if (!scheduledTime) return undefined;
  const trimmed = scheduledTime.trim();
  if (/^\d+(\.\d+)?$/.test(trimmed)) {
    const value = Number(trimmed);
    return value < 1e12 ? value * 1000 : value;
  }
  const parsed = Date.parse(trimmed);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function inEmulator(): boolean {
  return process.env.FUNCTIONS_EMULATOR === "true";
}

/**
 * True when the run must stop here because the task was put back for later.
 * Always false outside the emulator.
 */
export async function deferredInEmulator(
  queueName: string,
  req: { scheduledTime?: string; data: unknown }
): Promise<boolean> {
  if (!inEmulator()) return false;
  const due = scheduledTimeMillis(req.scheduledTime);
  if (due === undefined || due <= Date.now()) return false;

  await new Promise((resolve) => setTimeout(resolve, Math.min(due - Date.now(), MAX_WAIT_MS)));
  if (due <= Date.now()) return false;

  await getFunctions()
    .taskQueue(queueName)
    .enqueue(req.data as Record<string, unknown>, { scheduleTime: new Date(due) });
  logger.info(`[emulatorSchedule] ${queueName} not due yet; put back for ${new Date(due).toISOString()}`);
  return true;
}
