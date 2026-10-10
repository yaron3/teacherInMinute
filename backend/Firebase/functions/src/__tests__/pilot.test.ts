jest.mock("firebase-admin", () => ({ firestore: () => ({}) }));

import { buildApprovedEmail, normalizePilotEmail, pilotDocId } from "../pilot";

describe("normalizePilotEmail", () => {
  it("trims and lower-cases a valid address", () => {
    expect(normalizePilotEmail("  Someone@Gmail.COM ")).toBe("someone@gmail.com");
  });

  it("refuses non-addresses and characters unsafe in a document id or markup", () => {
    for (const bad of [undefined, 42, "", "no-at-sign", "a@b", "a b@x.com", "a/b@x.com", 'a"b@x.com', "a<b@x.com"]) {
      expect(normalizePilotEmail(bad)).toBeNull();
    }
  });
});

describe("pilotDocId", () => {
  it("keys a registration by app and address", () => {
    expect(pilotDocId("student", "a@x.com")).toBe("student:a@x.com");
  });
});

describe("buildApprovedEmail", () => {
  it("links the right package in the registrant's language", () => {
    const he = buildApprovedEmail("teacher", "he");
    expect(he.text).toContain("https://play.google.com/apps/testing/com.yaronj.tim");
    expect(he.text).toContain("https://play.google.com/store/apps/details?id=com.yaronj.tim");
    expect(he.subject).toContain("Pro Teacher");

    const en = buildApprovedEmail("student", "en");
    expect(en.text).toContain("com.yaronj.student");
    expect(en.subject).toBe("Instant Teacher is ready to download");
  });
});
