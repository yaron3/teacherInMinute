/**
 * Teacher payout method validation tests.
 *
 * Covers the pure parsing/validation in payoutMethod.ts — no Firebase calls.
 */

import {
  parsePayoutMethod,
  payoutMethodSummary,
  verifiedPayPalPayoutMethod,
  PayoutMethodValidationError,
} from "../payoutMethod";

describe("parsePayoutMethod — bank", () => {
  const valid = {
    type: "bank",
    bankCode: "12",
    branchNumber: "123",
    accountNumber: "45678901",
    accountHolderName: "Dana Cohen",
  };

  it("accepts a complete bank account", () => {
    expect(parsePayoutMethod(valid)).toEqual({
      ...valid,
      // Resolved from the code rather than taken from the client.
      bankName: "Bank Hapoalim",
    });
  });

  it("ignores a bank name supplied by the client", () => {
    const parsed = parsePayoutMethod({ ...valid, bankName: "Totally Not A Bank" });
    expect(parsed).toMatchObject({ bankCode: "12", bankName: "Bank Hapoalim" });
  });

  it("accepts a bank code that lost its leading zero", () => {
    expect(parsePayoutMethod({ ...valid, bankCode: "4" })).toMatchObject({
      bankCode: "04",
      bankName: "Bank Yahav",
    });
  });

  it.each([["99"], [""], ["abc"]])("rejects unknown bank code %p", (bankCode) => {
    expect(() => parsePayoutMethod({ ...valid, bankCode })).toThrow(PayoutMethodValidationError);
  });

  it("strips spaces and dashes from the numeric fields", () => {
    const parsed = parsePayoutMethod({ ...valid, branchNumber: "1 2 3", accountNumber: "456-789-01" });
    expect(parsed).toMatchObject({ branchNumber: "123", accountNumber: "45678901" });
  });

  it("trims surrounding whitespace from names", () => {
    const parsed = parsePayoutMethod({ ...valid, accountHolderName: "  Dana Cohen  " });
    expect(parsed).toMatchObject({ accountHolderName: "Dana Cohen" });
  });

  it.each([
    ["missing account holder", { ...valid, accountHolderName: "   " }],
    ["non-numeric account", { ...valid, accountNumber: "12ab34" }],
    ["too-short account", { ...valid, accountNumber: "12" }],
    ["too-long branch", { ...valid, branchNumber: "12345" }],
  ])("rejects %s", (_label, input) => {
    expect(() => parsePayoutMethod(input)).toThrow(PayoutMethodValidationError);
  });
});

describe("parsePayoutMethod — bit", () => {
  it("accepts a local mobile number", () => {
    expect(parsePayoutMethod({ type: "bit", phone: "052-123-4567" })).toEqual({
      type: "bit",
      phone: "0521234567",
    });
  });

  it("normalizes a +972 number to local form", () => {
    expect(parsePayoutMethod({ type: "bit", phone: "+972 52 123 4567" })).toEqual({
      type: "bit",
      phone: "0521234567",
    });
  });

  it.each([["", "empty"], ["12345", "too short"], ["5210", "no leading zero"]])(
    "rejects %s (%s)",
    (phone) => {
      expect(() => parsePayoutMethod({ type: "bit", phone })).toThrow(PayoutMethodValidationError);
    }
  );
});

describe("parsePayoutMethod — paypal", () => {
  it("accepts and lowercases an email", () => {
    expect(parsePayoutMethod({ type: "paypal", email: " Teacher@Example.COM " })).toEqual({
      type: "paypal",
      email: "teacher@example.com",
      verified: false,
    });
  });

  it("never trusts a client-supplied verified flag", () => {
    const parsed = parsePayoutMethod({ type: "paypal", email: "t@example.com", verified: true });
    expect(parsed).toMatchObject({ verified: false });
  });

  it("marks an email confirmed by PayPal itself as verified", () => {
    expect(verifiedPayPalPayoutMethod("Teacher@Example.com")).toEqual({
      type: "paypal",
      email: "teacher@example.com",
      verified: true,
    });
  });

  it.each([["no-at-sign"], ["missing@domain"], ["@example.com"], [""]])(
    "rejects %s",
    (email) => {
      expect(() => parsePayoutMethod({ type: "paypal", email })).toThrow(PayoutMethodValidationError);
    }
  );
});

describe("parsePayoutMethod — type", () => {
  it.each([[undefined], [{}], [{ type: "venmo" }], [{ type: "" }]])(
    "rejects an unsupported type (%p)",
    (input) => {
      expect(() => parsePayoutMethod(input)).toThrow(PayoutMethodValidationError);
    }
  );
});

describe("payoutMethodSummary", () => {
  it("masks a bank account to its last 4 digits", () => {
    const summary = payoutMethodSummary({
      type: "bank",
      bankCode: "12",
      bankName: "Bank Hapoalim",
      branchNumber: "123",
      accountNumber: "45678901",
      accountHolderName: "Dana Cohen",
    });
    expect(summary).toBe("Bank Hapoalim ••••8901");
    expect(summary).not.toContain("456789");
  });

  it("shows the phone for Bit and the email for PayPal", () => {
    expect(payoutMethodSummary({ type: "bit", phone: "0521234567" })).toBe("0521234567");
    expect(payoutMethodSummary({ type: "paypal", email: "t@example.com", verified: true })).toBe(
      "t@example.com"
    );
  });
});
