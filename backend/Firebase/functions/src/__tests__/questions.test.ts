const mockRtdbUpdate = jest.fn().mockResolvedValue(undefined);
const mockUserGet = jest.fn();
const mockQuestionSet = jest.fn().mockResolvedValue(undefined);
const mockQuestionUpdate = jest.fn().mockResolvedValue(undefined);
const mockMint = jest.fn();
const mockDispatchFirstWave = jest.fn();

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
    constructor(public code: string, message: string) {
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

describe("createQuestion", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    mockUserGet.mockResolvedValue({ data: () => ({ remainingMinutes: 20, fullName: "Sam" }) });
    mockDispatchFirstWave.mockResolvedValue(undefined);
    mockMint.mockResolvedValue({ token: "student-token", expiresAt: new Date() });
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
