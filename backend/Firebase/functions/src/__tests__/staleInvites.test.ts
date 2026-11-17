const mockArchiveUnanswered = jest.fn().mockResolvedValue(true);
const mockRemove = jest.fn().mockResolvedValue(undefined);
let mockInviteTree: unknown = null;
let mockSearching: { id: string; data: () => unknown }[] = [];

jest.mock("firebase-admin", () => ({
  database: jest.fn(() => ({
    ref: jest.fn((path: string) => ({
      once: jest.fn().mockResolvedValue({ val: () => (path === "teacherInvites" ? mockInviteTree : null) }),
      remove: () => mockRemove(path),
    })),
  })),
  firestore: jest.fn(() => ({
    collection: jest.fn(() => ({
      where: jest.fn(() => ({ get: jest.fn().mockResolvedValue({ docs: mockSearching }) })),
    })),
  })),
}));

jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

jest.mock("firebase-functions/v2/scheduler", () => ({
  onSchedule: jest.fn((_schedule: string, handler: unknown) => handler),
}));

jest.mock("../dispatch", () => ({
  archiveUnanswered: (...args: unknown[]) => mockArchiveUnanswered(...args),
}));

import {
  expiredInvitePaths,
  searchEndedAtMillis,
  sweepStaleQuestions,
  STALE_GRACE_SECONDS,
} from "../staleInvites";

const ts = (millis: number) => ({ toMillis: () => millis });
const NOW = 1_800_000_000_000;
const CUTOFF = NOW - STALE_GRACE_SECONDS * 1000;

beforeEach(() => {
  jest.clearAllMocks();
  mockInviteTree = null;
  mockSearching = [];
});

describe("expiredInvitePaths", () => {
  it("returns only cards that expired before the cutoff", () => {
    const tree = {
      teacherA: { oldQ: { expiresAt: CUTOFF - 1 }, liveQ: { expiresAt: CUTOFF + 1 } },
      teacherB: { oldQ: { expiresAt: CUTOFF - 60_000 } },
    };
    expect(expiredInvitePaths(tree, CUTOFF).sort()).toEqual([
      "teacherInvites/teacherA/oldQ",
      "teacherInvites/teacherB/oldQ",
    ]);
  });

  it("leaves cards without a numeric expiresAt, and copes with an empty tree", () => {
    expect(expiredInvitePaths({ t: { q: { expiresAt: "soon" }, r: {} } }, CUTOFF)).toEqual([]);
    expect(expiredInvitePaths(null, CUTOFF)).toEqual([]);
  });
});

describe("searchEndedAtMillis", () => {
  it("prefers searchEndsAt, falls back to createdAt + 90 s", () => {
    expect(searchEndedAtMillis({ searchEndsAt: ts(5), createdAt: ts(1) } as never)).toBe(5);
    expect(searchEndedAtMillis({ createdAt: ts(1000) } as never)).toBe(91_000);
    expect(searchEndedAtMillis({} as never)).toBeNull();
  });
});

describe("sweepStaleQuestions", () => {
  it("archives questions searching past their end and removes expired cards", async () => {
    mockSearching = [
      { id: "stuck", data: () => ({ status: "searching", searchEndsAt: ts(CUTOFF - 1), alreadyInvited: ["t1"] }) },
      { id: "fresh", data: () => ({ status: "searching", searchEndsAt: ts(NOW) }) },
    ];
    mockInviteTree = {
      t2: { stray: { expiresAt: CUTOFF - 1 }, live: { expiresAt: NOW + 60_000 } },
    };

    const result = await sweepStaleQuestions(NOW);

    expect(mockArchiveUnanswered).toHaveBeenCalledTimes(1);
    expect(mockArchiveUnanswered).toHaveBeenCalledWith("stuck", ["t1"]);
    expect(mockRemove).toHaveBeenCalledTimes(1);
    expect(mockRemove).toHaveBeenCalledWith("teacherInvites/t2/stray");
    expect(result).toEqual({ invitesRemoved: 1, questionsArchived: 1 });
  });

  it("leaves a card inside the grace period after its search ended", async () => {
    mockInviteTree = { t: { q: { expiresAt: NOW - 1 } } };
    expect(await sweepStaleQuestions(NOW)).toEqual({ invitesRemoved: 0, questionsArchived: 0 });
    expect(mockRemove).not.toHaveBeenCalled();
  });
});
