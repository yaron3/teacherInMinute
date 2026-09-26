jest.mock("firebase-functions", () => ({
  logger: { info: jest.fn(), warn: jest.fn(), error: jest.fn() },
}));

import { isTeacherBusy, isTeacherReachable, rankTeachers, scoreTeacher } from "../scoring";
import { TeacherRecord } from "../types";

const NOW = Date.now();

// Scores are read off the clock: a recency term that moves between two calls
// makes an exact comparison fail whenever a millisecond happens to tick, which
// is a flake rather than a finding. Pinning it makes every score here a
// function of its inputs alone.
let clock: jest.SpyInstance;
beforeEach(() => {
  clock = jest.spyOn(Date, "now").mockReturnValue(NOW);
});
afterEach(() => {
  clock.mockRestore();
});

function teacher(overrides: Partial<TeacherRecord> = {}): TeacherRecord {
  return {
    status: "online",
    subjects: ["algebra"],
    displayName: "Teacher",
    ...overrides,
  } as TeacherRecord;
}

function order(teachers: Record<string, TeacherRecord>, topic = "algebra"): string[] {
  return rankTeachers(teachers, topic, new Set<string>()).map((t) => t.uid);
}

describe("who gets the first wave", () => {
  test("the highest rated teacher comes first", () => {
    const ranked = order({
      good: teacher({ ratingAvg: 4.2, lastActiveAt: NOW }),
      best: teacher({ ratingAvg: 4.9, lastActiveAt: NOW }),
      poor: teacher({ ratingAvg: 2.1, lastActiveAt: NOW }),
    });

    expect(ranked).toEqual(["best", "good", "poor"]);
  });

  // The point of the prior: a teacher nobody has rated is not a bad teacher,
  // and must still be reachable — but cannot leapfrog an earned average.
  test("an unrated teacher sits between the good and the bad", () => {
    const ranked = order({
      rated_well: teacher({ ratingAvg: 4.5, lastActiveAt: NOW }),
      unrated: teacher({ lastActiveAt: NOW }),
      rated_badly: teacher({ ratingAvg: 1.5, lastActiveAt: NOW }),
    });

    expect(ranked).toEqual(["rated_well", "unrated", "rated_badly"]);
  });

  test("a rating of zero is treated as no rating, not as the worst possible", () => {
    expect(scoreTeacher(teacher({ ratingAvg: 0, lastActiveAt: NOW }))).toBe(
      scoreTeacher(teacher({ lastActiveAt: NOW }))
    );
  });
});

describe("records with fields missing", () => {
  // What iOS writes: status and subjects, nothing else. This used to score NaN,
  // and a comparator returning NaN leaves the order unspecified — so ranking
  // did not so much rank badly as not rank at all.
  test("a record carrying only status and subjects still scores", () => {
    const score = scoreTeacher(teacher());

    expect(Number.isFinite(score)).toBe(true);
    expect(score).toBeGreaterThan(0);
  });

  test("every partial record produces a usable order", () => {
    const ranked = order({
      bare: teacher(),
      rated: teacher({ ratingAvg: 5 }),
      stale: teacher({ ratingAvg: 5, lastActiveAt: NOW - 72 * 3_600_000 }),
    });

    expect(ranked).toHaveLength(3);
    expect(ranked[0]).toBe("rated");
    // Three days idle costs the recency term, so the same rating ranks lower.
    expect(ranked.indexOf("stale")).toBeGreaterThan(ranked.indexOf("rated"));
  });
});

describe("ties", () => {
  // Unrated teachers all score alike, so ties are ordinary. Left to the sort's
  // own stability the order would follow however the keys arrived, and the same
  // teachers would take wave 1 every time.
  test("are broken by who was active most recently, then by uid", () => {
    const ranked = order({
      zeta: teacher({ lastActiveAt: NOW - 1000 }),
      alpha: teacher({ lastActiveAt: NOW - 1000 }),
      recent: teacher({ lastActiveAt: NOW }),
    });

    expect(ranked).toEqual(["recent", "alpha", "zeta"]);
  });
});

describe("who is considered at all", () => {
  test("offline teachers are skipped whatever their rating", () => {
    expect(
      order({
        offline_star: teacher({ status: "offline", ratingAvg: 5 }),
        online: teacher({ ratingAvg: 3 }),
      })
    ).toEqual(["online"]);
  });

  test("a teacher who does not cover the topic is skipped", () => {
    expect(
      order({
        geometry: teacher({ subjects: ["geometry"], ratingAvg: 5 }),
        algebra: teacher({ subjects: ["algebra"] }),
      })
    ).toEqual(["algebra"]);
  });

  test("subjects still match when they carry their area", () => {
    expect(order({ prefixed: teacher({ subjects: ["Math: Algebra"] }) })).toEqual(["prefixed"]);
  });

  test("teachers already invited are excluded", () => {
    const ranked = rankTeachers(
      { invited: teacher({ ratingAvg: 5 }), fresh: teacher() },
      "algebra",
      new Set(["invited"])
    );

    expect(ranked.map((t) => t.uid)).toEqual(["fresh"]);
  });
});

describe("teachers in a session", () => {
  const MINUTE = 60_000;

  test("a busy teacher is not ranked, however well rated", () => {
    expect(
      order({
        teaching: teacher({ ratingAvg: 5, busy: { questionId: "q-1", since: NOW - 5 * MINUTE } }),
        free: teacher({ ratingAvg: 3 }),
      })
    ).toEqual(["free"]);
  });

  test("a mark older than any session can last is a lost clear, not a busy teacher", () => {
    const stale = teacher({ busy: { questionId: "q-1", since: NOW - 46 * MINUTE } });
    const current = teacher({ busy: { questionId: "q-1", since: NOW - 44 * MINUTE } });

    expect(isTeacherBusy(stale)).toBe(false);
    expect(isTeacherBusy(current)).toBe(true);
    expect(order({ stale })).toEqual(["stale"]);
  });

  test("no mark, or one without a question, is not busy", () => {
    expect(isTeacherBusy(teacher())).toBe(false);
    expect(
      isTeacherBusy(teacher({ busy: { questionId: "", since: NOW } as TeacherRecord["busy"] }))
    ).toBe(false);
  });
});

describe("teachers whose app has gone quiet", () => {
  const MINUTE = 60_000;

  test("a teacher whose app sent a keep-alive in the last three minutes is ranked", () => {
    expect(order({ alive: teacher({ lastSeenAt: NOW - 2 * MINUTE }) })).toEqual(["alive"]);
  });

  test("three silent minutes without a push token take a teacher out, however well rated", () => {
    expect(
      order({
        silent: teacher({ ratingAvg: 5, lastSeenAt: NOW - 3 * MINUTE }),
        alive: teacher({ ratingAvg: 3, lastSeenAt: NOW - 30_000 }),
      })
    ).toEqual(["alive"]);
  });

  test("a silent teacher with a push token is still reached", () => {
    expect(
      order({ pushable: teacher({ lastSeenAt: NOW - 60 * MINUTE, fcmToken: "fcm-token" }) })
    ).toEqual(["pushable"]);
  });

  test("an empty push token is no push token", () => {
    expect(isTeacherReachable(teacher({ lastSeenAt: NOW - 10 * MINUTE, fcmToken: "" }))).toBe(false);
  });

  // Installed apps update on their own schedule. One that has never sent a
  // keep-alive must not be read as one that stopped sending them.
  test("an app from before the keep-alive is judged on status alone", () => {
    expect(isTeacherReachable(teacher())).toBe(true);
    expect(order({ legacy: teacher() })).toEqual(["legacy"]);
  });

  test("the timeout is three minutes to the millisecond", () => {
    expect(isTeacherReachable(teacher({ lastSeenAt: NOW - 3 * MINUTE + 1 }))).toBe(true);
    expect(isTeacherReachable(teacher({ lastSeenAt: NOW - 3 * MINUTE }))).toBe(false);
  });
});
