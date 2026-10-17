jest.mock("firebase-admin", () => ({
  firestore: () => ({}),
}));

import { anonymousStudentRegistered, becameStudent, signupSlotsRemaining } from "../signupRewards";

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

describe("anonymousStudentRegistered", () => {
  it("fires when a linked anonymous student's profile stops being anonymous", () => {
    expect(anonymousStudentRegistered(
      { role: "student", isAnonymous: true },
      { role: "student", isAnonymous: false }
    )).toBe(true);
  });

  it.each([
    [{ role: "student", isAnonymous: true }, { role: "student", isAnonymous: true }],
    [{ role: "student" }, { role: "student", isAnonymous: false }],
    [undefined, { role: "student", isAnonymous: false }],
    [{ role: "student", isAnonymous: true }, undefined],
    [{ role: "student", isAnonymous: true }, { role: "teacher", isAnonymous: false }],
  ])("does not fire from %p to %p", (before, after) => {
    expect(anonymousStudentRegistered(before, after)).toBe(false);
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
