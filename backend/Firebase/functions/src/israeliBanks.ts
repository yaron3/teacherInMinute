// ─── Israeli banks ───────────────────────────────────────────────────────────
//
// The banks a teacher can pick as a payout destination. Picking from this list
// (rather than typing a bank name freehand) is what makes the bank field
// checkable at all: it removes misspellings and pins each entry to a code.
//
// ⚠️ VERIFY BEFORE PRODUCTION: these codes are the commonly published Israeli
// bank codes, but they have NOT been checked against the Bank of Israel's
// official list, and several listed banks have merged over the years (Igud into
// Mizrahi-Tefahot, Otsar Ha-Hayal into FIBI). Confirm the codes and which banks
// still accept transfers before relying on them for real payouts.
//
// What this file deliberately does NOT do: per-bank account-number check
// digits. Each Israeli bank uses its own weighted mod-11 scheme, and
// implementing them from memory would reject valid accounts — worse than not
// checking. Add them here (keyed by code) if you obtain the specifications.

export interface IsraeliBank {
  /** Official bank code, as used on transfers. */
  code: string;
  /** English name, shown when the app is in English. */
  name: string;
  /** Hebrew name, shown when the app is in Hebrew. */
  nameHe: string;
}

export const ISRAELI_BANKS: readonly IsraeliBank[] = [
  { code: "04", name: "Bank Yahav", nameHe: "בנק יהב" },
  { code: "09", name: "Bank HaDoar", nameHe: "בנק הדואר" },
  { code: "10", name: "Bank Leumi", nameHe: "בנק לאומי" },
  { code: "11", name: "Bank Discount", nameHe: "בנק דיסקונט" },
  { code: "12", name: "Bank Hapoalim", nameHe: "בנק הפועלים" },
  { code: "13", name: "Bank Igud", nameHe: "בנק אגוד" },
  { code: "14", name: "Bank Otsar Ha-Hayal", nameHe: "בנק אוצר החייל" },
  { code: "17", name: "Mercantile Discount Bank", nameHe: "בנק מרכנתיל דיסקונט" },
  { code: "18", name: "One Zero", nameHe: "וואן זירו" },
  { code: "20", name: "Bank Mizrahi-Tefahot", nameHe: "בנק מזרחי טפחות" },
  { code: "26", name: "UBank", nameHe: "יובנק" },
  { code: "31", name: "First International Bank", nameHe: "הבנק הבינלאומי הראשון" },
  { code: "34", name: "Arab Israeli Bank", nameHe: "הבנק הערבי הישראלי" },
  { code: "46", name: "Bank Massad", nameHe: "בנק מסד" },
  { code: "52", name: "Bank PAGI", nameHe: "בנק פאג\"י" },
  { code: "54", name: "Bank of Jerusalem", nameHe: "בנק ירושלים" },
];

const BANKS_BY_CODE = new Map(ISRAELI_BANKS.map((bank) => [bank.code, bank]));

/** Looks up a bank by its code, tolerating a missing leading zero
 *  ("4" for Yahav) since pickers and hand entry disagree about it. */
export function findBankByCode(code: unknown): IsraeliBank | undefined {
  if (typeof code !== "string" && typeof code !== "number") return undefined;
  const raw = String(code).trim();
  if (!raw) return undefined;
  return BANKS_BY_CODE.get(raw) ?? BANKS_BY_CODE.get(raw.padStart(2, "0"));
}
