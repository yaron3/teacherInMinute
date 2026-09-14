const mockRtdbUpdate = jest.fn().mockResolvedValue(undefined);
const mockUserGet = jest.fn();
const mockQuestionSet = jest.fn().mockResolvedValue(undefined);
const mockQuestionUpdate = jest.fn().mockResolvedValue(undefined);
const mockMint = jest.fn();
const mockDispatchFirstWave = jest.fn();
const mockQuestionMaxLength = jest.fn();
const mockRateLimits = jest.fn();
const mockCheckAllowance = jest.fn();

jest.mock("firebase-admin", () => ({
  database: jest.fn(() => ({
    ref: jest.fn(() => ({ update: mockRtdbUpdate })),
  })),
  firestore: jest.fn(() => ({
    collection: jest.fn((name: string) => ({
      doc: jest.fn(() =>
        name === "users"
          ? { get: mockUserGet }
          : { set: mockQuestionSet, update: mockQuestionUpdate }
      ),
    })),
  })),
}));

jest.mock("firebase-admin/firestore", () => ({
  FieldValue: { serverTimestamp: jest.fn() },
  Timestamp: { now: jest.fn(() => "now") },
}));

jest.mock("firebase-functions", () => ({
  logger: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

jest.mock("firebase-functions/v2/https", () => ({
  onCall: jest.fn((_options: unknown, handler: unknown) => handler),
  HttpsError: class HttpsError extends Error {
    constructor(public code: string, message: string, public details?: unknown) {
      super(message);
    }
  },
}));

jest.mock("uuid", () => ({ v4: jest.fn(() => "q-1") }));

jest.mock("../livekit", () => ({
  ...jest.requireActual("../livekit"),
  mintLiveKitToken: (...args: unknown[]) => mockMint(...args),
}));

jest.mock("../fcm", () => ({ sendAcceptedPush: jest.fn() }));

jest.mock("../pricing", () => ({
  getConnectionFeeCents: jest.fn().mockResolvedValue(50),
}));

jest.mock("../stats", () => ({ recordQuestionConnected: jest.fn() }));

jest.mock("../questionLimits", () => ({
  getQuestionMaxLength: () => mockQuestionMaxLength(),
  getQuestionRateLimits: () => mockRateLimits(),
}));

jest.mock("../rateLimit", () => ({
  checkQuestionAllowance: (...args: unknown[]) => mockCheckAllowance(...args),
  recordSessionStart: jest.fn().mockResolvedValue(undefined),
}));

jest.mock("../dispatch", () => ({
  dispatchFirstWave: (...args: unknown[]) => mockDispatchFirstWave(...args),
  enqueueQuestionWatchdog: jest.fn().mockResolvedValue(undefined),
}));

import { createQuestion } from "../questions";

type CallableHandler = (request: {
  auth?: { uid: string };
  data: Record<string, unknown>;
}) => Promise<Record<string, unknown>>;

const createQuestionHandler = createQuestion as unknown as CallableHandler;

function ask(conversationType: string) {
  return createQuestionHandler({
    auth: { uid: "student-1" },
    data: { topic: "algebra", text: "How do I solve 2x + 3 = 11?", conversationType },
  });
}

function askWithText(text: string) {
  return createQuestionHandler({
    auth: { uid: "student-1" },
    data: { topic: "algebra", text, conversationType: "text" },
  });
}

function askWithPhotos(photoUrls: unknown) {
  return createQuestionHandler({
    auth: { uid: "student-1" },
    data: {
      topic: "algebra",
      text: "How do I solve 2x + 3 = 11?",
      photoUrls,
      conversationType: "text",
    },
  });
}

/** What StorageService.uploadQuestionImage returns for this student. */
function ownPhotoUrl(uid = "student-1"): string {
  return (
    "https://firebasestorage.googleapis.com/v0/b/teacher-in-a-moment.firebasestorage.app/o/" +
    `${encodeURIComponent(`questionImages/${uid}/1757000000000.jpg`)}?alt=media&token=t`
  );
}

describe("createQuestion", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockUserGet.mockResolvedValue({ data: () => ({ remainingMinutes: 20, fullName: "Sam" }) });
    mockDispatchFirstWave.mockResolvedValue(undefined);
    mockMint.mockResolvedValue({ token: "student-token", expiresAt: new Date() });
    mockQuestionMaxLength.mockResolvedValue(1024);
    mockRateLimits.mockResolvedValue({ perMinute: 2, perHour: 5 });
    mockCheckAllowance.mockResolvedValue({ allowed: true, kept: [] });
  });

  describe("question photos", () => {
    const originalProject = process.env.GCLOUD_PROJECT;

    beforeEach(() => {
      process.env.GCLOUD_PROJECT = "teacher-in-a-moment";
    });

    afterAll(() => {
      if (originalProject === undefined) delete process.env.GCLOUD_PROJECT;
      else process.env.GCLOUD_PROJECT = originalProject;
    });

    test("accepts and stores a photo the student uploaded", async () => {
      await expect(askWithPhotos([ownPhotoUrl()])).resolves.toEqual({
        questionId: "q-1",
        connectionFeeCents: 50,
      });
      expect(mockQuestionSet).toHaveBeenCalledWith(
        expect.objectContaining({ photoUrls: [ownPhotoUrl()] })
      );
    });

    test.each([
      ["a link to somewhere else entirely", "https://evil.test/tracker.jpg"],
      ["another student's upload", ownPhotoUrl("student-2")],
    ])("rejects %s, before writing anything", async (_label, url) => {
      await expect(askWithPhotos([url])).rejects.toMatchObject({
        code: "invalid-argument",
        details: { reason: "photo_url_rejected" },
      });
      expect(mockQuestionSet).not.toHaveBeenCalled();
      expect(mockRtdbUpdate).not.toHaveBeenCalled();
      expect(mockDispatchFirstWave).not.toHaveBeenCalled();
    });

    test("rejects a question whose photos are partly foreign", async () => {
      await expect(
        askWithPhotos([ownPhotoUrl(), "https://evil.test/tracker.jpg"])
      ).rejects.toMatchObject({ details: { reason: "photo_url_rejected" } });
    });

    test("stores an array even when the client sends something else", async () => {
      await expect(askWithPhotos([42, null])).resolves.toEqual({
        questionId: "q-1",
        connectionFeeCents: 50,
      });
      expect(mockQuestionSet).toHaveBeenCalledWith(expect.objectContaining({ photoUrls: [] }));
    });
  });

  describe("how often a student may start a lesson", () => {
    test("refuses once the allowance is spent, and writes nothing", async () => {
      mockCheckAllowance.mockResolvedValue({
        allowed: false,
        scope: "minute",
        retryAfterSeconds: 20,
        kept: [],
      });

      await expect(ask("text")).rejects.toMatchObject({
        code: "resource-exhausted",
        details: { reason: "rate_limited", scope: "minute", retryAfterSeconds: 20 },
      });

      expect(mockQuestionSet).not.toHaveBeenCalled();
      expect(mockRtdbUpdate).not.toHaveBeenCalled();
      expect(mockDispatchFirstWave).not.toHaveBeenCalled();
    });

    test("passes the published allowances through", async () => {
      mockRateLimits.mockResolvedValue({ perMinute: 7, perHour: 9 });

      await ask("text");

      expect(mockCheckAllowance).toHaveBeenCalledWith("student-1", 7, 9);
    });

    // An allowance is for questions that would otherwise have gone out; a
    // malformed one must not cost the student anything.
    test("does not even check a question that was refused for another reason", async () => {
      await expect(askWithText("too short")).rejects.toThrow();
      expect(mockCheckAllowance).not.toHaveBeenCalled();
    });

    test("does not check when the student has no minutes", async () => {
      mockUserGet.mockResolvedValue({ data: () => ({ remainingMinutes: 0 }) });

      await expect(ask("text")).rejects.toMatchObject({ code: "resource-exhausted" });
      expect(mockCheckAllowance).not.toHaveBeenCalled();
    });
  });

  describe("question length", () => {
    // The app shows its own localized sentence for this, so the reason and the
    // limit have to survive the trip — not just the English message.
    test("rejects text longer than the limit, before writing anything", async () => {
      await expect(askWithText("x".repeat(1025))).rejects.toMatchObject({
        code: "invalid-argument",
        message: "Question text must be at most 1024 characters",
        details: { reason: "question_too_long", limit: 1024 },
      });
      expect(mockQuestionSet).not.toHaveBeenCalled();
      expect(mockRtdbUpdate).not.toHaveBeenCalled();
      expect(mockDispatchFirstWave).not.toHaveBeenCalled();
    });

    test("accepts text exactly at the limit", async () => {
      await expect(askWithText("x".repeat(1024))).resolves.toEqual({
        questionId: "q-1",
        connectionFeeCents: 50,
      });
    });

    // Trailing whitespace is not part of what gets stored, so it must not be
    // what pushes a question over the limit.
    test("measures the limit after trimming", async () => {
      await expect(askWithText(`   ${"x".repeat(1024)}   `)).resolves.toEqual({
        questionId: "q-1",
        connectionFeeCents: 50,
      });
    });

    test("follows the limit Remote Config publishes", async () => {
      mockQuestionMaxLength.mockResolvedValue(20);

      await expect(askWithText("x".repeat(21))).rejects.toMatchObject({
        message: "Question text must be at most 20 characters",
        details: { reason: "question_too_long", limit: 20 },
      });
      await expect(askWithText("x".repeat(20))).resolves.toEqual({
        questionId: "q-1",
        connectionFeeCents: 50,
      });
    });
  });

  test.each(["audio", "video"])(
    "hands a %s question's student their LiveKit credentials",
    async (conversationType) => {
      // Minted alongside the dispatch rather than after it, so the question
      // reaches teachers no later than it did before.
      let mintedBeforeDispatch = false;
      mockDispatchFirstWave.mockImplementation(async () => {
        mintedBeforeDispatch = mockMint.mock.calls.length > 0;
      });

      await expect(ask(conversationType)).resolves.toEqual({
        questionId: "q-1",
        connectionFeeCents: 50,
        liveKitRoom: "lesson_q-1",
        liveKitToken: "student-token",
      });
      expect(mockMint).toHaveBeenCalledWith("lesson_q-1", "student-1");
      expect(mintedBeforeDispatch).toBe(true);
    }
  );

  test("mints nothing for a text question", async () => {
    await expect(ask("text")).resolves.toEqual({ questionId: "q-1", connectionFeeCents: 50 });
    expect(mockMint).not.toHaveBeenCalled();
  });

  test("still creates the question when the token cannot be minted", async () => {
    mockMint.mockRejectedValue(new Error("LIVEKIT_API_KEY and LIVEKIT_API_SECRET must be set"));

    await expect(ask("audio")).resolves.toEqual({ questionId: "q-1", connectionFeeCents: 50 });
    expect(mockQuestionSet).toHaveBeenCalled();
    expect(mockDispatchFirstWave).toHaveBeenCalled();
  });
});
