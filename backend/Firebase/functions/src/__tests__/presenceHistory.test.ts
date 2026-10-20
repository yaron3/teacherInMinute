/**
 * The hourly online-teacher history the admin console averages over.
 */

import { fakeFirestore, resetFakeFirebase } from "./support/fakeFirebase";

jest.mock("firebase-admin", () => {
  const fake = require("./support/fakeFirebase");
  return { database: () => fake.fakeRtdb, firestore: () => fake.fakeFirestore };
});

import {
  PRESENCE_HOURLY_COLLECTION,
  recordOnlineTeacherSample,
  summarizeOnlineTeachers,
} from "../presenceHistory";

const HOUR = 60 * 60_000;
const DAY = 24 * HOUR;
const NOON = Date.UTC(2026, 9, 20, 12, 0, 0);

beforeEach(() => resetFakeFirebase(NOON));

describe("recordOnlineTeacherSample", () => {
  test("folds each sweep into the hour's bucket", async () => {
    await recordOnlineTeacherSample(["anna", "ben"], NOON + 60_000);
    await recordOnlineTeacherSample(["anna", "carl"], NOON + 120_000);

    expect(fakeFirestore.read(`${PRESENCE_HOURLY_COLLECTION}/${NOON}`)).toEqual({
      hourStartMs: NOON,
      samples: 2,
      onlineSum: 4,
      uids: ["anna", "ben", "carl"],
    });
  });

  test("starts a new bucket each hour", async () => {
    await recordOnlineTeacherSample(["anna"], NOON + 59 * 60_000);
    await recordOnlineTeacherSample([], NOON + HOUR);

    expect(Object.keys(fakeFirestore.readCollection(PRESENCE_HOURLY_COLLECTION)).sort())
      .toEqual([String(NOON), String(NOON + HOUR)]);
  });
});

describe("summarizeOnlineTeachers", () => {
  test("averages the minutes sampled and the distinct teachers per hour", async () => {
    // Hour 1: 2 online for 2 sweeps. Hour 2: 0 online for 2 sweeps.
    await recordOnlineTeacherSample(["anna", "ben"], NOON);
    await recordOnlineTeacherSample(["anna", "ben"], NOON + 60_000);
    await recordOnlineTeacherSample([], NOON + HOUR);
    await recordOnlineTeacherSample([], NOON + HOUR + 60_000);

    expect(await summarizeOnlineTeachers(NOON + HOUR + 120_000, DAY)).toEqual({
      avgOnline: 1,
      avgDistinctPerHour: 1,
      hoursCovered: 2,
    });
  });

  test("leaves out hours older than the window", async () => {
    await recordOnlineTeacherSample(["anna", "ben", "carl"], NOON - DAY);
    await recordOnlineTeacherSample(["anna"], NOON);

    expect(await summarizeOnlineTeachers(NOON, DAY)).toEqual({
      avgOnline: 1,
      avgDistinctPerHour: 1,
      hoursCovered: 1,
    });
  });

  test("reports nothing rather than zero before any history exists", async () => {
    expect(await summarizeOnlineTeachers(NOON, DAY)).toEqual({
      avgOnline: null,
      avgDistinctPerHour: null,
      hoursCovered: 0,
    });
  });
});
