jest.mock("firebase-admin", () => ({
  firestore: () => ({}),
}));

import {
  appDeepLink,
  buildLandingPage,
  buildVerificationEmail,
  languageFromHeader,
  linkStatusForClaim,
  throttleSends,
  tokenId,
} from "../emailVerification";
import { ClaimResponse, EmailRewardOffer, studentSlotsRemaining } from "../emailRewards";

const offer: EmailRewardOffer = {
  studentMinutes: 30,
  studentSlots: 100,
  teacherShare: 1,
  teacherBonusMinutes: 300,
};

function claim(overrides: Partial<ClaimResponse>): ClaimResponse {
  return {
    status: "granted",
    role: "student",
    studentMinutes: 30,
    studentSlotsRemaining: 99,
    teacherShare: 1,
    teacherBonusMinutes: 300,
    teacherBonusMinutesRemaining: 0,
    ...overrides,
  };
}

describe("studentSlotsRemaining", () => {
  it("is the cap less the students already rewarded", () => {
    expect(studentSlotsRemaining(offer, 0)).toBe(100);
    expect(studentSlotsRemaining(offer, 37)).toBe(63);
  });

  it("treats a missing counter as nobody rewarded yet", () => {
    expect(studentSlotsRemaining(offer, undefined)).toBe(100);
  });

  it("reaches 0 at the cap and never goes below it", () => {
    expect(studentSlotsRemaining(offer, 100)).toBe(0);
    expect(studentSlotsRemaining(offer, 140)).toBe(0);
  });

  it("is 0 when the cap is set to 0", () => {
    expect(studentSlotsRemaining({ ...offer, studentSlots: 0 }, 0)).toBe(0);
  });
});

describe("throttleSends", () => {
  const now = 10_000_000;

  it("allows the first send", () => {
    expect(throttleSends(undefined, now)).toEqual({ allowed: true, kept: [] });
  });

  it("refuses a send within 30 seconds of the last", () => {
    expect(throttleSends([now - 10_000], now).allowed).toBe(false);
    expect(throttleSends([now - 31_000], now).allowed).toBe(true);
  });

  it("refuses a sixth send inside the hour and forgets older ones", () => {
    const five = [1, 2, 3, 4, 5].map((i) => now - i * 60_000);
    expect(throttleSends(five, now).allowed).toBe(false);
    expect(throttleSends([now - 2 * 3_600_000, ...five.slice(0, 4)], now)).toEqual({
      allowed: true,
      kept: five.slice(0, 4).sort((a, b) => a - b),
    });
  });
});

describe("linkStatusForClaim", () => {
  it.each([
    ["granted", "granted"],
    ["promotion_ended", "promotion_ended"],
    ["already_granted", "already_granted"],
    ["claimed_by_other_account", "claimed_by_other_account"],
    ["not_eligible", "verified"],
    ["unavailable", "verified"],
    ["not_verified", "verified"],
  ] as const)("maps %s to %s", (status, expected) => {
    expect(linkStatusForClaim(claim({ status }))).toBe(expected);
  });
});

describe("appDeepLink", () => {
  it("opens the student app with the minutes added", () => {
    expect(appDeepLink("student", "granted", claim({ minutesAdded: 30 }))).toBe(
      "teacherminute://email-verified?status=granted&minutes=30"
    );
  });

  it("opens the teacher app with the bonus", () => {
    const teacher = claim({ role: "teacher", teacherShare: 1, teacherBonusMinutesRemaining: 300 });
    expect(appDeepLink("teacher", "granted", teacher)).toBe(
      "proteacher://email-verified?status=granted&percent=100&bonusMinutes=300"
    );
  });

  it("carries only the status when nothing was granted", () => {
    expect(appDeepLink("student", "promotion_ended", claim({ status: "promotion_ended" }))).toBe(
      "teacherminute://email-verified?status=promotion_ended"
    );
    expect(appDeepLink("student", "expired")).toBe("teacherminute://email-verified?status=expired");
  });
});

describe("pages and mail", () => {
  it("says the promotion ended and opens the app", () => {
    const link = appDeepLink("student", "promotion_ended");
    const page = buildLandingPage("promotion_ended", link, "en");
    expect(page).toContain("promotion has ended");
    expect(page).toContain(JSON.stringify(link));
  });

  it("writes Hebrew right to left", () => {
    expect(buildLandingPage("granted", "teacherminute://x", "he")).toContain('dir="rtl"');
    expect(buildVerificationEmail("https://l", "student", "he").html).toContain('dir="rtl"');
  });

  it("puts the link in both parts of the email", () => {
    const mail = buildVerificationEmail("https://example.test/verifyEmailLink?t=abc", "student", "en");
    expect(mail.text).toContain("https://example.test/verifyEmailLink?t=abc");
    expect(mail.html).toContain('href="https://example.test/verifyEmailLink?t=abc"');
    expect(mail.subject).toBe("Verify your email for Instant Teacher");
  });

  it("stores tokens hashed", () => {
    expect(tokenId("abc")).toMatch(/^[0-9a-f]{64}$/);
    expect(tokenId("abc")).not.toContain("abc");
  });
});

describe("languageFromHeader", () => {
  it("is English when the browser says nothing", () => {
    expect(languageFromHeader(undefined)).toBe("en");
    expect(languageFromHeader("")).toBe("en");
  });

  it("is Hebrew when the browser prefers it", () => {
    expect(languageFromHeader("he-IL,he;q=0.9,en-US;q=0.8")).toBe("he");
    expect(languageFromHeader("iw")).toBe("he");
    expect(languageFromHeader("en;q=0.5, he;q=0.8")).toBe("he");
  });

  it("is English when the browser prefers it or names neither", () => {
    expect(languageFromHeader("en-US,en;q=0.9,he;q=0.8")).toBe("en");
    expect(languageFromHeader("fr-FR,de;q=0.9")).toBe("en");
    expect(languageFromHeader("*")).toBe("en");
  });

  it("lets the first listed win a tie", () => {
    expect(languageFromHeader("he, en")).toBe("he");
    expect(languageFromHeader("en, he")).toBe("en");
  });
});
