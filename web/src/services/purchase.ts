import { collection, doc, getDocs, onSnapshot } from "firebase/firestore";
import { httpsCallable } from "firebase/functions";
import { firestore, functions } from "./firebase";

// Buying minutes, as the apps do: packages come from the public `pricing`
// collection; `createCheckoutSession` opens a checkout for one and returns the
// hosted card page (Tranzila), and the backend credits the minutes once the
// payment is confirmed server to server. The page never sees a card number.

export interface MinutesPackage {
  id: string;
  name: string;
  description: string;
  minutes: number;
  priceCents: number;
  currency: string;
  highlighted: boolean;
}

/** Active packages in their sort order, one per distinct offer (PricingService). */
export async function fetchPackages(languageCode: "en" | "he"): Promise<MinutesPackage[]> {
  const snap = await getDocs(collection(firestore, "pricing"));
  const rows = snap.docs
    .map((d) => ({ id: d.id, data: d.data() }))
    .filter(({ data }) => data.active !== false)
    .map(({ id, data }) => {
      const local = (key: string) => String(data[`${languageCode}_${key}`] ?? "").trim() || String(data[key] ?? "").trim();
      return {
        id,
        sortOrder: Number(data.sortOrder ?? 0),
        pkg: {
          id,
          name: local("name"),
          description: local("description"),
          minutes: Number(data.minutes ?? data.minutesGranted ?? 0),
          priceCents: Math.floor(Number(data.priceCents ?? 0)),
          currency: currencyCode(String(data.currency ?? "ILS")),
          highlighted: data.isHighlighted === true,
        } satisfies MinutesPackage,
      };
    })
    .filter(({ pkg }) => pkg.name && pkg.minutes > 0 && pkg.priceCents > 0)
    .sort((a, b) => a.sortOrder - b.sortOrder);
  const seen = new Set<string>();
  return rows
    .map((r) => r.pkg)
    .filter((p) => {
      const key = [p.name, p.minutes, p.priceCents, p.currency].join("|");
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
}

/** Opens a card checkout for a package; returns the page to pay on and the
 *  checkout's id, to follow it. */
export async function startCheckout(packageId: string): Promise<{ url: string; checkoutId: string }> {
  const result = await httpsCallable<object, { checkoutUrl?: string }>(functions, "createCheckoutSession")({
    pricingOptionId: packageId,
    paymentMethod: "credit_card",
    platform: "web",
  });
  const url = result.data.checkoutUrl;
  if (!url) throw new Error("no checkout URL");
  const checkoutId = new URL(url).searchParams.get("checkoutId") ?? "";
  return { url, checkoutId };
}

export type CheckoutState = "pending" | "completed" | "cancelled";

/** Follows `paymentCheckouts/{id}`, which only its buyer may read. */
export function watchCheckout(checkoutId: string, onChange: (state: CheckoutState) => void): () => void {
  return onSnapshot(
    doc(firestore, "paymentCheckouts", checkoutId),
    (snap) => {
      const status = String(snap.data()?.status ?? "");
      onChange(status === "completed" ? "completed" : status === "cancelled" ? "cancelled" : "pending");
    },
    (e) => console.error("[purchase] checkout listener failed", e),
  );
}

/** A currency code as Intl takes it. Stored codes are not always clean:
 *  staging's package has `"ILS"`, quotes included. */
export function currencyCode(raw: string): string {
  const code = raw.replace(/[^A-Za-z]/g, "").toUpperCase();
  return code.length === 3 ? code : "ILS";
}

/** A price as LessonFormatting.currencyText writes it: no ".00" on a whole
 *  amount. */
export function formatPrice(cents: number, currency: string, locale: string) {
  const code = currencyCode(currency);
  const whole = cents % 100 === 0;
  try {
    return new Intl.NumberFormat(locale, {
      style: "currency",
      currency: code,
      minimumFractionDigits: whole ? 0 : 2,
      maximumFractionDigits: whole ? 0 : 2,
    }).format(cents / 100);
  } catch {
    return `${(cents / 100).toFixed(whole ? 0 : 2)} ${code}`;
  }
}
