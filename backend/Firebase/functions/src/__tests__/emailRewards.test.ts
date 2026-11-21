jest.mock("firebase-admin", () => ({
  firestore: () => ({}),
}));

import { canonicalEmailIdentity, emailClaimId, readTeacherBonus } from "../emailRewards";

describe("canonicalEmailIdentity", () => {
  it.each([
    ["Jane.Doe@Gmail.com", "janedoe@gmail.com"],
    ["j.a.n.e.d.o.e@gmail.com", "janedoe@gmail.com"],
    ["janedoe+promo@gmail.com", "janedoe@gmail.com"],
    ["jane.doe+1+2@googlemail.com", "janedoe@gmail.com"],
    ["  JANEDOE@GMAIL.COM ", "janedoe@gmail.com"],
  ])("folds Gmail alias %s into one mailbox", (raw, expected) => {
    expect(canonicalEmailIdentity(raw)).toBe(expected);
  });

  it("drops +tags on any domain", () => {
    expect(canonicalEmailIdentity("me+teacher@outlook.com")).toBe("me@outlook.com");
    expect(canonicalEmailIdentity("me+x@school.org.il")).toBe("me@school.org.il");
  });

  it("keeps dots outside Gmail, where they can name different people", () => {
    expect(canonicalEmailIdentity("j.doe@outlook.com")).toBe("j.doe@outlook.com");
    expect(canonicalEmailIdentity("j.doe@outlook.com")).not.toBe(
      canonicalEmailIdentity("jdoe@outlook.com")
    );
  });

  it("does not collapse a local part that is only a +tag", () => {
    expect(canonicalEmailIdentity("+abc@example.com")).toBe("+abc@example.com");
    expect(canonicalEmailIdentity("+abc@example.com")).not.toBe(
      canonicalEmailIdentity("+xyz@example.com")
    );
  });

  it("returns empty for anything that is not an address", () => {
    expect(canonicalEmailIdentity("")).toBe("");
    expect(canonicalEmailIdentity("nodomain@")).toBe("");
    expect(canonicalEmailIdentity("@example.com")).toBe("");
    expect(canonicalEmailIdentity(undefined)).toBe("");
  });
});

describe("emailClaimId", () => {
  it("is the same for every alias of a mailbox and holds no plaintext", () => {
    const a = emailClaimId(canonicalEmailIdentity("Jane.Doe+x@gmail.com"));
    const b = emailClaimId(canonicalEmailIdentity("janedoe@googlemail.com"));
    expect(a).toBe(b);
    expect(a).toMatch(/^[0-9a-f]{64}$/);
  });
});

describe("readTeacherBonus", () => {
  it("reads a live bonus", () => {
    expect(readTeacherBonus({ share: 1, minutesRemaining: 120 })).toEqual({
      share: 1,
      minutesRemaining: 120,
    });
  });

  it.each([
    [undefined],
    [null],
    [{ share: 1, minutesRemaining: 0 }],
    [{ share: 1, minutesRemaining: -3 }],
    [{ share: 0, minutesRemaining: 10 }],
    [{ share: 1.5, minutesRemaining: 10 }],
    [{ minutesRemaining: 10 }],
  ])("treats %p as no bonus", (value) => {
    expect(readTeacherBonus(value)).toBeUndefined();
  });
});
