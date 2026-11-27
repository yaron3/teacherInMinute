// ─── Purchase windows for the admin dashboard ────────────────────────────────
//
// Completed purchases in the last 24 hours, 7 days and 30 days, rolling from
// now. Money is kept per currency throughout: a shekel purchase is never added
// to a dollar one.

const DAY_MS = 24 * 3600 * 1000;

export const PURCHASE_WINDOWS = [
  { key: "day", label: "24 hours", ms: DAY_MS },
  { key: "week", label: "7 days", ms: 7 * DAY_MS },
  { key: "month", label: "30 days", ms: 30 * DAY_MS },
] as const;

export type PurchaseWindowKey = (typeof PURCHASE_WINDOWS)[number]["key"];

/** What the summary needs from a `paymentCheckouts` document. */
export interface PurchaseRow {
  uid: string;
  status: string;
  currency: string;
  priceCents: number;
  minutes: number;
  /** Which method or processor paid: paypal, card, apple_pay, google_pay… */
  method: string;
  createdAtMs: number | null;
  completedAtMs: number | null;
}

export interface PurchaseWindow {
  /** Completed purchases. */
  count: number;
  /** Distinct buyers among them. */
  buyers: number;
  /** Revenue in cents, per currency. */
  byCurrency: Record<string, number>;
  /** Completed purchases per payment method. */
  byMethod: Record<string, number>;
  minutes: number;
  /** Checkouts opened in the window that never completed. */
  abandoned: number;
}

function emptyWindow(): PurchaseWindow {
  return { count: 0, buyers: 0, byCurrency: {}, byMethod: {}, minutes: 0, abandoned: 0 };
}

/**
 * Buckets purchases into the three windows. A completed purchase is dated by
 * when it completed (falling back to when it opened); an abandoned one is a
 * checkout opened in the window that did not complete. Demo users are left
 * out, as everywhere else on the dashboard.
 */
export function summarizePurchases(
  rows: PurchaseRow[],
  nowMs: number,
  demoUids: Set<string>
): Record<PurchaseWindowKey, PurchaseWindow> {
  const out = {} as Record<PurchaseWindowKey, PurchaseWindow>;
  for (const w of PURCHASE_WINDOWS) {
    const since = nowMs - w.ms;
    const win = emptyWindow();
    const buyers = new Set<string>();
    for (const r of rows) {
      if (demoUids.has(r.uid)) continue;
      if (r.status === "completed") {
        const at = r.completedAtMs ?? r.createdAtMs;
        if (at === null || at < since || at > nowMs) continue;
        win.count += 1;
        buyers.add(r.uid);
        win.byCurrency[r.currency] = (win.byCurrency[r.currency] ?? 0) + r.priceCents;
        win.byMethod[r.method] = (win.byMethod[r.method] ?? 0) + 1;
        win.minutes += r.minutes;
      } else if (r.createdAtMs !== null && r.createdAtMs >= since && r.createdAtMs <= nowMs) {
        // Still open, or closed without paying: either way, not a sale.
        win.abandoned += 1;
      }
    }
    win.buyers = buyers.size;
    out[w.key] = win;
  }
  return out;
}

/** The method a checkout was paid with, as the Payments page names it. */
export function purchaseMethod(data: Record<string, unknown>): string {
  const chosen = typeof data.paymentMethod === "string" && data.paymentMethod ? data.paymentMethod : null;
  if (chosen) return chosen;
  if (data.paypalCaptureId || data.paypalOrderId) return "paypal";
  if (data.tranzilaTransactionId) return "card";
  if (data.braintreeTransactionId) return "braintree";
  return "other";
}
