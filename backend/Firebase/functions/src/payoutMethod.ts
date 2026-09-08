// ─── Teacher payout method ───────────────────────────────────────────────────
//
// Where a teacher's monthly payout is sent. One of three kinds, each with its
// own required fields:
//
//   bank   — Israeli bank transfer: bank name, branch, account number, holder
//   bit    — Bit transfer to a phone number
//   paypal — PayPal transfer to an email address
//
// Pure parsing and validation, kept free of firebase-admin so it can be unit
// tested. The callable in ./earnings.ts persists whatever this returns.

import { findBankByCode } from "./israeliBanks";

export type PayoutMethodType = "bank" | "bit" | "paypal";

export const PAYOUT_METHOD_TYPES: readonly PayoutMethodType[] = ["bank", "bit", "paypal"];

export interface BankPayoutMethod {
  type: "bank";
  /** Official bank code, from ./israeliBanks. */
  bankCode: string;
  /** Resolved from the code rather than trusted from the client, so the stored
   *  name can never disagree with the code the money is sent to. */
  bankName: string;
  branchNumber: string;
  accountNumber: string;
  accountHolderName: string;
}

export interface BitPayoutMethod {
  type: "bit";
  phone: string;
}

export interface PayPalPayoutMethod {
  type: "paypal";
  email: string;
  /** True when the email came back from a completed PayPal login rather than
   *  being typed in — see verifyPayPalPayoutAccount in ./earnings. */
  verified: boolean;
}

export type PayoutMethod = BankPayoutMethod | BitPayoutMethod | PayPalPayoutMethod;

/** Raised for input a teacher can fix by correcting the form. The message is
 *  shown to them, so it names the specific field that is wrong. */
export class PayoutMethodValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PayoutMethodValidationError";
  }
}

function text(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

/** Digits only — Israeli bank and phone fields are commonly typed with spaces
 *  and dashes, which carry no meaning and would break exact comparisons. */
function digits(value: unknown): string {
  return text(value).replace(/[\s-]/g, "");
}

function requireDigits(value: unknown, field: string, min: number, max: number): string {
  const cleaned = digits(value);
  if (!cleaned) throw new PayoutMethodValidationError(`Missing ${field}`);
  if (!/^\d+$/.test(cleaned)) throw new PayoutMethodValidationError(`${field} must contain digits only`);
  if (cleaned.length < min || cleaned.length > max) {
    throw new PayoutMethodValidationError(`${field} must be ${min}-${max} digits`);
  }
  return cleaned;
}

function requireText(value: unknown, field: string, max = 100): string {
  const cleaned = text(value);
  if (!cleaned) throw new PayoutMethodValidationError(`Missing ${field}`);
  if (cleaned.length > max) throw new PayoutMethodValidationError(`${field} is too long`);
  return cleaned;
}

/** Israeli mobile numbers, with or without the +972 country code. Stored in
 *  local 0-prefixed form so it matches what the teacher typed on their profile. */
function requirePhone(value: unknown): string {
  let cleaned = digits(value).replace(/^\+/, "");
  if (cleaned.startsWith("972")) cleaned = `0${cleaned.slice(3)}`;
  if (!/^0\d{8,9}$/.test(cleaned)) {
    throw new PayoutMethodValidationError("Enter a valid phone number");
  }
  return cleaned;
}

function requireEmail(value: unknown): string {
  const cleaned = text(value).toLowerCase();
  // Deliberately loose: a full RFC check rejects addresses that work fine, and
  // PayPal is the real authority on whether the account exists.
  if (!/^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$/.test(cleaned)) {
    throw new PayoutMethodValidationError("Enter a valid email address");
  }
  return cleaned;
}

/** Validates and normalizes a payout method submitted by the app.
 *  Throws `PayoutMethodValidationError` for anything a teacher can correct. */
export function parsePayoutMethod(input: unknown): PayoutMethod {
  const data = (input ?? {}) as Record<string, unknown>;
  const type = text(data.type).toLowerCase();

  switch (type) {
    case "bank": {
      // The bank must be one we know, so a typo cannot become a payout
      // destination. The name is taken from the list, not from the client.
      const bank = findBankByCode(data.bankCode);
      if (!bank) throw new PayoutMethodValidationError("Choose a bank from the list");
      return {
        type: "bank",
        bankCode: bank.code,
        bankName: bank.name,
        // Israeli branch numbers are 3 digits; account numbers vary by bank,
        // so the range is deliberately wide. Note there is no per-bank check
        // digit here — see the note in ./israeliBanks.
        branchNumber: requireDigits(data.branchNumber, "branch number", 2, 4),
        accountNumber: requireDigits(data.accountNumber, "account number", 4, 20),
        accountHolderName: requireText(data.accountHolderName, "account holder name"),
      };
    }
    case "bit":
      return { type: "bit", phone: requirePhone(data.phone) };
    case "paypal":
      return {
        type: "paypal",
        email: requireEmail(data.email),
        // Only a completed PayPal login can set this, and that path builds the
        // method server-side — a client claim of `verified` is ignored.
        verified: false,
      };
    default:
      throw new PayoutMethodValidationError(
        `Unsupported payout method "${type || "(missing)"}"`
      );
  }
}

/** A short, non-sensitive description of where the money goes — safe to show
 *  in the app's payout summary. Bank accounts are masked to the last 4 digits. */
export function payoutMethodSummary(method: PayoutMethod): string {
  switch (method.type) {
    case "bank":
      return `${method.bankName} ••••${method.accountNumber.slice(-4)}`;
    case "bit":
      return method.phone;
    case "paypal":
      return method.email;
  }
}

/** Builds a PayPal method from an email PayPal itself confirmed, bypassing the
 *  typed-in path so `verified` can only ever be set from a real login. */
export function verifiedPayPalPayoutMethod(email: string): PayPalPayoutMethod {
  return { type: "paypal", email: requireEmail(email), verified: true };
}
