jest.mock("firebase-admin/firestore", () => ({
  Timestamp: { now: () => ({ toMillis: () => 1_700_000_000_000 }) },
}));

import {
  emailRewardMessage,
  inboxDocument,
  INBOX_MESSAGE_IDS,
  signupMinutesMessage,
  verificationSentMessage,
} from "../inboxMessages";

const offer = { studentMinutes: 10, teacherShare: 1, teacherBonusMinutes: 300 };

// IT-51: what signing up and the welcome rewards leave in the bell.
describe("verificationSentMessage", () => {
  test("tells a teacher where the link went and what verifying unlocks", () => {
    const message = verificationSentMessage("teacher", "t@example.com", offer);
    expect(message.title).toBe("Your account is ready");
    expect(message.text).toContain("t@example.com");
    expect(message.text).toContain("keep 100% of your earnings for your first 300 minutes");
    expect(message.textHe).toContain("t@example.com");
    expect(message.textHe).toContain("100%");
    expect(message.textHe).toContain("300");
  });

  test("offers a student the free minutes", () => {
    const message = verificationSentMessage("student", "s@example.com", offer);
    expect(message.text).toContain("get 10 free minutes");
    expect(message.textHe).toContain("10 דקות חינם");
  });

  test("promises nothing once the offer is off or over", () => {
    expect(verificationSentMessage("student", "s@example.com", undefined).text).not.toContain("free minutes");
    const off = verificationSentMessage("teacher", "t@example.com", { ...offer, teacherBonusMinutes: 0 });
    expect(off.text).not.toContain("earnings");
    expect(off.textHe).not.toContain("%");
  });
});

describe("emailRewardMessage", () => {
  test("a teacher's bonus, with its share as a percentage", () => {
    const message = emailRewardMessage("teacher", { ...offer, teacherShare: 0.9 });
    expect(message.title).toBe("Welcome bonus unlocked");
    expect(message.text).toContain("keep 90% of your earnings for your next 300 minutes");
    expect(message.titleHe).toBe("בונוס ההצטרפות הופעל");
  });

  test("a student's minutes", () => {
    const message = emailRewardMessage("student", offer);
    expect(message.title).toBe("10 free minutes added");
    expect(message.titleHe).toBe("נוספו 10 דקות חינם");
  });
});

describe("signupMinutesMessage", () => {
  test("names the minutes in both languages", () => {
    const message = signupMinutesMessage(15);
    expect(message.title).toBe("15 free minutes added");
    expect(message.text).toContain("15 free minutes");
    expect(message.textHe).toContain("15 דקות חינם");
  });
});

describe("inboxDocument", () => {
  test("stamps the kind and the time, with a fixed id per kind", () => {
    const doc = inboxDocument("signupMinutes", signupMinutesMessage(5));
    expect(doc).toMatchObject({ kind: "signupMinutes", title: "5 free minutes added" });
    expect(doc.createdAt).toBeDefined();
    expect(new Set(Object.values(INBOX_MESSAGE_IDS)).size).toBe(3);
  });
});
