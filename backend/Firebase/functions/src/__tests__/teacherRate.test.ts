const mockRc = new Map<string, number>();

jest.mock("firebase-admin", () => ({ firestore: () => ({}) }));
jest.mock("firebase-functions", () => ({ logger: { warn: jest.fn() } }));
jest.mock("../remoteConfig", () => ({
  readRcNumber: jest.fn(async (key: string) => mockRc.get(key)),
}));

import { teacherEarningsFor } from "../billing";
import { parseAdminTeacherRate, resolveTeacherRatePerMinute } from "../pricing";

beforeEach(() => mockRc.clear());

describe("parseAdminTeacherRate", () => {
  it("rounds a valid rate to agorot", () => expect(parseAdminTeacherRate(1.876)).toBe(1.88));
  it("takes null as back to the default", () => expect(parseAdminTeacherRate(null)).toBeNull());
  it.each([0, -1, 0.001, 100.01, Number.NaN, "2", undefined])("rejects %p", (value) => {
    expect(parseAdminTeacherRate(value)).toBeUndefined();
  });
});

describe("resolveTeacherRatePerMinute", () => {
  it("defaults to 2 ILS", async () => {
    await expect(resolveTeacherRatePerMinute({}, "ILS")).resolves.toBe(2);
  });

  it("takes the default from Remote Config", async () => {
    mockRc.set("teacher_rate_per_minute_ils", 1.6);
    await expect(resolveTeacherRatePerMinute(undefined, "ILS")).resolves.toBe(1.6);
  });

  it("prefers the teacher's own rate", async () => {
    mockRc.set("teacher_rate_per_minute_ils", 1.6);
    await expect(resolveTeacherRatePerMinute({ teacherRatePerMinuteIls: 2.5 }, "ILS")).resolves.toBe(2.5);
  });

  it("does not follow the student's price", async () => {
    mockRc.set("price_per_minute_ils", 7);
    await expect(resolveTeacherRatePerMinute({}, "ILS")).resolves.toBe(2);
  });

  it.each([0, -1, Number.NaN, "3"])("ignores an unusable own rate: %p", async (value) => {
    await expect(resolveTeacherRatePerMinute({ teacherRatePerMinuteIls: value }, "ILS")).resolves.toBe(2);
  });

  it("converts for a lesson billed in USD", async () => {
    mockRc.set("exchange_rate_ils", 4);
    await expect(resolveTeacherRatePerMinute({}, "USD")).resolves.toBe(0.5);
  });
});

describe("teacherEarningsFor", () => {
  it("is the minutes at the rate", () => expect(teacherEarningsFor(10, 2)).toBe(20));
  it("keeps agorot exact", () => expect(teacherEarningsFor(3, 1.1)).toBe(3.3));
  it("is nothing for a free lesson", () => expect(teacherEarningsFor(0, 2)).toBe(0));
});
