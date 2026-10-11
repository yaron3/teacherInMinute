jest.mock("firebase-admin", () => ({
  firestore: () => ({}),
}));

import { becameStudent, signupSlotsRemaining } from "../signupRewards";

describe("becameStudent", () => {
  it.each([
    [undefined, "student"],
    [null, "student"],
    ["teacher", "student"],
  ])("fires when the role goes from %p to student", (before, after) => {
    expect(becameStudent(before, after)).toBe(true);
  });

  it.each([
    ["student", "student"],
    [undefined, "teacher"],
    ["student", "teacher"],
    ["student", undefined],
    [undefined, undefined],
  ])("does not fire from %p to %p", (before, after) => {
    expect(becameStudent(before, after)).toBe(false);
  });
});

describe("signupSlotsRemaining", () => {
  const offer = { minutes: 30, slots: 100 };

  it("is the cap less those granted", () => {
    expect(signupSlotsRemaining(offer, 40)).toBe(60);
  });

  it("treats a missing or unreadable count as none granted", () => {
    expect(signupSlotsRemaining(offer, undefined)).toBe(100);
    expect(signupSlotsRemaining(offer, "abc")).toBe(100);
  });

  it("never goes below zero", () => {
    expect(signupSlotsRemaining(offer, 250)).toBe(0);
  });
});
