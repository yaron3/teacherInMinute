/**
 * The emulator-only wait for delayed tasks (../emulatorSchedule): reading the
 * scheduled time from either header format, and doing nothing in production.
 */
const mockEnqueue = jest.fn(async () => undefined);
jest.mock("firebase-admin/functions", () => ({
  getFunctions: () => ({ taskQueue: () => ({ enqueue: mockEnqueue }) }),
}));
jest.mock("firebase-functions", () => ({ logger: { info: jest.fn() } }));

import { deferredInEmulator, scheduledTimeMillis } from "../emulatorSchedule";

describe("scheduledTimeMillis", () => {
  test("reads Cloud Tasks' seconds since the epoch", () => {
    expect(scheduledTimeMillis("1794306846.5")).toBe(1794306846500);
  });

  test("reads the emulator's ISO date", () => {
    expect(scheduledTimeMillis("2026-11-10T10:00:00.000Z")).toBe(Date.parse("2026-11-10T10:00:00.000Z"));
  });

  test("reads milliseconds", () => {
    expect(scheduledTimeMillis("1794306846500")).toBe(1794306846500);
  });

  test("gives up on anything else", () => {
    expect(scheduledTimeMillis(undefined)).toBeUndefined();
    expect(scheduledTimeMillis("soon")).toBeUndefined();
  });
});

describe("deferredInEmulator", () => {
  const saved = process.env.FUNCTIONS_EMULATOR;
  afterEach(() => {
    if (saved === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = saved;
    mockEnqueue.mockClear();
  });

  test("never waits or re-enqueues outside the emulator", async () => {
    delete process.env.FUNCTIONS_EMULATOR;
    const future = new Date(Date.now() + 60_000).toISOString();
    await expect(deferredInEmulator("questionWatchdog", { scheduledTime: future, data: {} })).resolves.toBe(false);
    expect(mockEnqueue).not.toHaveBeenCalled();
  });

  test("runs a task that is already due on the emulator", async () => {
    process.env.FUNCTIONS_EMULATOR = "true";
    const past = new Date(Date.now() - 1_000).toISOString();
    await expect(deferredInEmulator("questionWatchdog", { scheduledTime: past, data: {} })).resolves.toBe(false);
    expect(mockEnqueue).not.toHaveBeenCalled();
  });

  test("waits out a short delay on the emulator, then runs", async () => {
    process.env.FUNCTIONS_EMULATOR = "true";
    const soon = new Date(Date.now() + 300).toISOString();
    const started = Date.now();
    await expect(deferredInEmulator("evaluateWave", { scheduledTime: soon, data: {} })).resolves.toBe(false);
    expect(Date.now() - started).toBeGreaterThanOrEqual(250);
    expect(mockEnqueue).not.toHaveBeenCalled();
  });
});
