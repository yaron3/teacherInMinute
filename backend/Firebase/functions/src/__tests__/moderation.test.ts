/**
 * Reporting and blocking teachers.
 *
 * Covers the pure pieces — validating a report, the email it sends, and who a
 * question's dispatch leaves out — with no Firebase calls.
 */

jest.mock("firebase-admin", () => ({
  firestore: jest.fn(() => ({})),
  database: jest.fn(() => ({})),
}));

import {
  buildReportEmail,
  MAX_REPORT_DETAILS_LENGTH,
  parseReportRequest,
} from "../moderation";
import { dispatchExclusions } from "../dispatch";

describe("parseReportRequest", () => {
  it("accepts a report with a known reason, trimming the details", () => {
    expect(
      parseReportRequest({ questionId: " q1 ", reason: "harassment", details: "  rude  ", block: true })
    ).toEqual({ questionId: "q1", reason: "harassment", details: "rude", block: true });
  });

  it("treats a missing details and block as empty and false", () => {
    expect(parseReportRequest({ questionId: "q1", reason: "other" })).toEqual({
      questionId: "q1",
      reason: "other",
      details: "",
      block: false,
    });
  });

  it("only blocks on a literal true", () => {
    expect(parseReportRequest({ questionId: "q1", reason: "other", block: "yes" }).block).toBe(false);
  });

  it("rejects a missing question", () => {
    expect(() => parseReportRequest({ reason: "other" })).toThrow("questionId is required");
  });

  it("rejects an unknown reason", () => {
    expect(() => parseReportRequest({ questionId: "q1", reason: "boring" })).toThrow("reason must be one of");
  });

  it("rejects details over the limit", () => {
    const details = "x".repeat(MAX_REPORT_DETAILS_LENGTH + 1);
    expect(() => parseReportRequest({ questionId: "q1", reason: "other", details })).toThrow(
      "details must be at most"
    );
  });
});

describe("buildReportEmail", () => {
  const report = {
    id: "r1",
    reason: "sexual" as const,
    details: "Said something inappropriate",
    blocked: true,
    questionId: "q1",
    reporterUid: "s1",
    reporterName: "Dana",
    reporterEmail: "dana@example.com",
    teacherUid: "t1",
    teacherName: "Michael\r\nBcc: x@example.com",
  };

  it("keeps user text out of the subject's headers", () => {
    const { subject } = buildReportEmail(report);
    expect(subject).not.toMatch(/[\r\n]/);
    expect(subject).toContain("sexual");
  });

  it("carries everything support needs to act", () => {
    const { text } = buildReportEmail(report);
    for (const part of ["Said something inappropriate", "Blocked by the student: yes", "t1", "s1", "q1", "r1"]) {
      expect(text).toContain(part);
    }
  });
});

describe("dispatchExclusions", () => {
  it("leaves out blocked teachers as well as invited ones", () => {
    expect(dispatchExclusions({ blockedTeachers: ["t2"] }, ["t1"])).toEqual(new Set(["t1", "t2"]));
  });

  it("is just the invited teachers for a question with no blocks", () => {
    expect(dispatchExclusions({}, ["t1"])).toEqual(new Set(["t1"]));
  });
});
