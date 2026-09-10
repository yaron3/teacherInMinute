const mockQuestionUpdate = jest.fn().mockResolvedValue(undefined);
const mockQueueEnqueue = jest.fn().mockResolvedValue(undefined);
const mockServerTimestamp = { kind: "server-timestamp" };

const mockDbRef = jest.fn((path: string) => {
  if (path === "teachers") {
    // dispatch.ts asks for only the online teachers:
    //   ref("teachers").orderByChild("status").equalTo("online").once("value")
    const query = {
      once: jest.fn().mockResolvedValue({ val: () => ({}) }),
    };
    return {
      orderByChild: jest.fn(() => ({ equalTo: jest.fn(() => query) })),
    };
  }

  return {
    once: jest.fn().mockResolvedValue({ exists: () => false, val: () => null }),
    remove: jest.fn().mockResolvedValue(undefined),
    set: jest.fn().mockResolvedValue(undefined),
  };
});

/** What the claim transaction reads. Set per test to drive who owns wave 1. */
let questionForClaim: Record<string, unknown> | null = null;

const mockTransactionUpdate = jest.fn();
const mockRunTransaction = jest.fn(async (work: (tx: unknown) => Promise<unknown>) =>
  work({
    get: jest.fn().mockResolvedValue({
      exists: questionForClaim !== null,
      data: () => questionForClaim,
    }),
    update: mockTransactionUpdate,
  })
);

const mockFirestore = {
  collection: jest.fn(() => ({
    doc: jest.fn(() => ({
      update: mockQuestionUpdate,
    })),
  })),
  runTransaction: mockRunTransaction,
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

import { dispatchQuestion, dispatchFirstWave } from "../dispatch";
import { QuestionDoc } from "../types";

type TriggerHandler = (event: {
  params: { qid: string };
  data: { data: () => Record<string, unknown> };
}) => Promise<void>;

function searchingQuestion(overrides: Record<string, unknown> = {}) {
  return {
    studentUid: "student-1",
    topic: "algebra",
    text: "Please help with this equation",
    photoUrls: [],
    conversationType: "text",
    status: "searching",
    dispatchWave: 0,
    alreadyInvited: [],
    ...overrides,
  };
}

describe("dispatchFirstWave", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    questionForClaim = null;
  });

  test("keeps a new question searchable when no teacher is immediately eligible", async () => {
    await dispatchFirstWave("question-1", searchingQuestion() as unknown as QuestionDoc);

    // No teacher was invited, so there is nothing to record beyond the touch.
    expect(mockQuestionUpdate).toHaveBeenCalledWith({ updatedAt: mockServerTimestamp });
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

describe("dispatchQuestion", () => {
  beforeEach(() => {
    jest.clearAllMocks();
    questionForClaim = null;
  });

  // createQuestion dispatches wave 1 itself and writes the question already
  // marked dispatchWave: 1. The trigger must recognise that and do nothing,
  // or every question would be fanned out twice.
  //
  // Note the event payload says dispatchWave: 0 while the stored document says
  // 1 — that is the case the trigger has to get right. It must decide from the
  // current document, not from the snapshot it was handed.
  test("stands down when createQuestion already dispatched wave 1 inline", async () => {
    questionForClaim = searchingQuestion({ dispatchWave: 1 });
    const handler = dispatchQuestion as unknown as TriggerHandler;

    await handler({
      params: { qid: "question-1" },
      data: { data: () => searchingQuestion({ dispatchWave: 0 }) },
    });

    expect(mockQueueEnqueue).not.toHaveBeenCalled();
    expect(mockQuestionUpdate).not.toHaveBeenCalled();
  });

  // The mirror image: the event says wave 1 was claimed, but the inline
  // dispatch failed and handed it back, so the stored document says 0. The
  // trigger must recover the question rather than trust the stale payload.
  test("recovers when the event says wave 1 but the document says otherwise", async () => {
    questionForClaim = searchingQuestion({ dispatchWave: 0 });
    const handler = dispatchQuestion as unknown as TriggerHandler;

    await handler({
      params: { qid: "question-1" },
      data: { data: () => searchingQuestion({ dispatchWave: 1 }) },
    });

    expect(mockTransactionUpdate).toHaveBeenCalledWith(expect.anything(), {
      dispatchWave: 1,
      updatedAt: mockServerTimestamp,
    });
    expect(mockQueueEnqueue).toHaveBeenCalledWith(
      "evaluateWave",
      { questionId: "question-1", wave: 1 },
      { scheduleDelaySeconds: 12 }
    );
  });

  // The safety net: createQuestion wrote the question but never fanned it out,
  // so dispatchWave is still 0 and the trigger has to pick the question up.
  test("recovers a question whose inline dispatch never ran", async () => {
    questionForClaim = searchingQuestion();
    const handler = dispatchQuestion as unknown as TriggerHandler;

    await handler({
      params: { qid: "question-1" },
      data: { data: () => searchingQuestion() },
    });

    expect(mockRunTransaction).toHaveBeenCalled();
    expect(mockTransactionUpdate).toHaveBeenCalledWith(expect.anything(), {
      dispatchWave: 1,
      updatedAt: mockServerTimestamp,
    });
    expect(mockQueueEnqueue).toHaveBeenCalledWith(
      "evaluateWave",
      { questionId: "question-1", wave: 1 },
      { scheduleDelaySeconds: 12 }
    );
  });

  // Two claimants racing: whoever loses the transaction must not fan out.
  test("stands down when the claim transaction finds the wave taken", async () => {
    questionForClaim = searchingQuestion({ dispatchWave: 1 });
    const handler = dispatchQuestion as unknown as TriggerHandler;

    await handler({
      params: { qid: "question-1" },
      data: { data: () => searchingQuestion() },
    });

    expect(mockRunTransaction).toHaveBeenCalled();
    expect(mockTransactionUpdate).not.toHaveBeenCalled();
    expect(mockQueueEnqueue).not.toHaveBeenCalled();
  });
});
