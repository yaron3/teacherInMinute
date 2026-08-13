const mockQuestionUpdate = jest.fn().mockResolvedValue(undefined);
const mockQueueEnqueue = jest.fn().mockResolvedValue(undefined);
const mockServerTimestamp = { kind: "server-timestamp" };

const mockDbRef = jest.fn((path: string) => {
  if (path === "teachers") {
    return {
      once: jest.fn().mockResolvedValue({ val: () => ({}) }),
    };
  }

  return {
    once: jest.fn().mockResolvedValue({ exists: () => false, val: () => null }),
    remove: jest.fn().mockResolvedValue(undefined),
    set: jest.fn().mockResolvedValue(undefined),
  };
});

const mockFirestore = {
  collection: jest.fn(() => ({
    doc: jest.fn(() => ({
      update: mockQuestionUpdate,
    })),
  })),
};

jest.mock("firebase-admin", () => ({
  database: jest.fn(() => ({ ref: mockDbRef })),
  firestore: jest.fn(() => mockFirestore),
}));

jest.mock("firebase-admin/firestore", () => ({
  FieldValue: {
    serverTimestamp: jest.fn(() => mockServerTimestamp),
    arrayUnion: jest.fn((...values: unknown[]) => ({ kind: "array-union", values })),
  },
  Timestamp: {
    now: jest.fn(),
    fromMillis: jest.fn(),
  },
}));

jest.mock("firebase-admin/functions", () => ({
  getFunctions: jest.fn(() => ({
    taskQueue: jest.fn((name: string) => ({
      enqueue: (payload: unknown, options: unknown) => mockQueueEnqueue(name, payload, options),
    })),
  })),
}));

jest.mock("firebase-functions", () => ({
  logger: {
    info: jest.fn(),
    warn: jest.fn(),
    error: jest.fn(),
  },
}));

jest.mock("firebase-functions/v2/firestore", () => ({
  onDocumentCreated: jest.fn((_path: string, handler: unknown) => handler),
}));

jest.mock("firebase-functions/v2/tasks", () => ({
  onTaskDispatched: jest.fn((_options: unknown, handler: unknown) => handler),
}));

jest.mock("firebase-functions/v2/database", () => ({
  onValueWritten: jest.fn((_path: string, handler: unknown) => handler),
}));

jest.mock("../fcm", () => ({
  sendInvitePush: jest.fn(),
  sendNoMatchPush: jest.fn(),
}));

jest.mock("../scoring", () => ({
  rankTeachers: jest.fn(() => []),
}));

import { dispatchQuestion } from "../dispatch";

describe("dispatchQuestion", () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  test("keeps a new question searchable when no teacher is immediately eligible", async () => {
    const handler = dispatchQuestion as unknown as (event: {
      params: { qid: string };
      data: { data: () => Record<string, unknown> };
    }) => Promise<void>;

    await handler({
      params: { qid: "question-1" },
      data: {
        data: () => ({
          studentUid: "student-1",
          topic: "algebra",
          text: "Please help with this equation",
          photoUrls: [],
          conversationType: "text",
          status: "searching",
          dispatchWave: 0,
          alreadyInvited: [],
        }),
      },
    });

    expect(mockQuestionUpdate).toHaveBeenCalledWith({
      dispatchWave: 1,
      updatedAt: mockServerTimestamp,
    });
    expect(mockDbRef).not.toHaveBeenCalledWith("questions/question-1");
    expect(mockQueueEnqueue).toHaveBeenCalledWith(
      "evaluateWave",
      { questionId: "question-1", wave: 1 },
      { scheduleDelaySeconds: 12 }
    );
    expect(mockQueueEnqueue).toHaveBeenCalledWith(
      "questionWatchdog",
      { questionId: "question-1" },
      { scheduleDelaySeconds: 90 }
    );
  });
});
