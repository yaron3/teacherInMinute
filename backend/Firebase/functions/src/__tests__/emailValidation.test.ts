import { normalizeEmail, isValidEmailSyntax, domainOf } from "../emailValidation";

describe("normalizeEmail", () => {
  it("trims and lowercases so typed case never breaks a comparison", () => {
    expect(normalizeEmail("  Name@Example.COM ")).toBe("name@example.com");
  });

  it("treats a non-string as empty rather than throwing", () => {
    expect(normalizeEmail(undefined)).toBe("");
    expect(normalizeEmail(42)).toBe("");
  });
});

describe("isValidEmailSyntax", () => {
  it.each([
    "a@b.co",
    "name@example.com",
    "first.last@sub.domain.co.il",
    "teacher+payouts@gmail.com",
    "user_name@example-domain.com",
  ])("accepts %s", (email) => {
    expect(isValidEmailSyntax(email)).toBe(true);
  });

  it.each([
    ["", "empty"],
    ["plainaddress", "no @"],
    ["@example.com", "no local part"],
    ["name@", "no domain"],
    ["name@localhost", "domain without a dot"],
    ["name@exam ple.com", "whitespace"],
    ["name@@example.com", "double @ leaves an empty label"],
    [".name@example.com", "leading dot in local part"],
    ["name.@example.com", "trailing dot in local part"],
    ["na..me@example.com", "consecutive dots"],
    ["name@-example.com", "domain label starting with a hyphen"],
    ["name@example-.com", "domain label ending with a hyphen"],
    ["name@example..com", "empty domain label"],
    ["name@exa_mple.com", "underscore in the domain"],
  ])("rejects %s (%s)", (email) => {
    expect(isValidEmailSyntax(email)).toBe(false);
  });

  it("rejects an over-long local part", () => {
    expect(isValidEmailSyntax(`${"a".repeat(65)}@example.com`)).toBe(false);
    expect(isValidEmailSyntax(`${"a".repeat(64)}@example.com`)).toBe(true);
  });
});

describe("domainOf", () => {
  it("returns the part after the last @", () => {
    expect(domainOf("name@example.com")).toBe("example.com");
  });
});
