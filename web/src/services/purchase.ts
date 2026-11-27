import { FirebaseError } from "firebase/app";
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

export type PayMethod = "card" | "paypal" | "apple_pay" | "google_pay";

/** Apple Pay is offered where the browser can pay with it: Safari on a Mac or
 *  an iPhone with a card in Wallet. The payment page shows Apple's own button. */
export function applePayAvailable(): boolean {
  const session = (window as unknown as { ApplePaySession?: { canMakePayments(): boolean } }).ApplePaySession;
  try {
    return !!session && session.canMakePayments();
  } catch {
    return false;
  }
}

/** The methods this browser is offered, in the apps' order
 *  (PaymentMethod.configuredForCheckout): its own wallet — Apple Pay in
 *  Safari, Google Pay elsewhere while Remote Config's `enable_google_pay` is
 *  on — then PayPal and card. */
export function availablePayMethods(googlePayEnabled: boolean): PayMethod[] {
  const wallet: PayMethod[] = applePayAvailable() ? ["apple_pay"] : googlePayEnabled ? ["google_pay"] : [];
  return [...wallet, "paypal", "card"];
}

/** Thrown when the backend has no web page for a wallet (Apple Pay or Google
 *  Pay through Braintree need the app's native sheet), or says it is off. */
export class WalletUnavailableError extends Error {}

/** The page the payment pages end on (backend allowedWebReturnUrl): inside the
 *  checkout sheet it tells the app how the payment ended (`watchPaymentReturn`). */
function webReturnUrl(): string {
  return new URL(`${import.meta.env.BASE_URL}payment-return.html`, location.origin).toString();
}

export type PaymentOutcome = "success" | "cancelled" | "no_response";

/** What public/payment-return.html reports from inside the checkout sheet. */
export function watchPaymentReturn(onReturn: (outcome: PaymentOutcome, checkoutId: string) => void): () => void {
  const listener = (e: MessageEvent) => {
    if (e.origin !== location.origin) return;
    const data = e.data as { source?: string; status?: string; checkoutId?: string } | null;
    if (data?.source !== "tim-payment") return;
    if (data.status === "success" || data.status === "cancelled" || data.status === "no_response") {
      onReturn(data.status, data.checkoutId ?? "");
    }
  };
  window.addEventListener("message", listener);
  return () => window.removeEventListener("message", listener);
}

const CALLABLE: Record<PayMethod, string> = {
  card: "createCheckoutSession",
  paypal: "createCheckoutSession", // only for the app's redirect flow; the web uses the buttons
  apple_pay: "createApplePayCheckout",
  google_pay: "createGooglePayCheckout",
};

/** Opens a checkout for a package and returns the page to pay on and the
 *  checkout's id, to follow it: the card page, PayPal's approval page, or the
 *  card page with Apple Pay or Google Pay on it. */
export async function startCheckout(packageId: string, method: PayMethod = "card"): Promise<{ url: string; checkoutId: string }> {
  const wallet = method === "apple_pay" || method === "google_pay";
  let data: { checkoutUrl?: string; checkoutId?: string };
  try {
    ({ data } = await httpsCallable<object, { checkoutUrl?: string; checkoutId?: string }>(functions, CALLABLE[method])({
      pricingOptionId: packageId,
      // No method is PayPal's own checkout (createCheckoutSession).
      ...(method === "card" ? { paymentMethod: "credit_card" } : {}),
      platform: "web",
      webReturnUrl: webReturnUrl(),
    }));
  } catch (e) {
    // The backend's "not available yet" for a wallet it cannot run.
    if (wallet && e instanceof FirebaseError && e.code === "functions/failed-precondition") {
      throw new WalletUnavailableError(`${method} is not available`);
    }
    throw e;
  }
  const url = data.checkoutUrl;
  if (!url) {
    if (wallet) throw new WalletUnavailableError(`${method} has no web page`);
    throw new Error("no checkout URL");
  }
  const checkoutId = data.checkoutId ?? new URL(url).searchParams.get("checkoutId") ?? "";
  return { url, checkoutId };
}

/** What the payment pages said when they sent the buyer back
 *  (`?payment=success|cancelled|no_response&checkout_id=…`), read once. */
export function takePaymentReturn(): { status: "success" | "cancelled" | "no_response"; checkoutId: string } | null {
  const params = new URLSearchParams(location.search);
  const status = params.get("payment");
  if (status !== "success" && status !== "cancelled" && status !== "no_response") return null;
  history.replaceState(null, "", `${import.meta.env.BASE_URL}#buy`);
  return { status, checkoutId: params.get("checkout_id") ?? "" };
}

// ─── PayPal buttons (JS SDK standard checkout) ────────────────────────────────
// PayPal's own buttons on the page: createOrder opens the checkout
// (createCheckoutSession, PayPal's order), PayPal runs the approval in its
// popup, and onApprove has the backend capture it (capturePayPalOrder).

export interface PayPalButtonsApi {
  Buttons(options: {
    style?: Record<string, unknown>;
    createOrder: () => Promise<string>;
    onApprove: (data: { orderID: string }) => Promise<void>;
    onCancel?: () => void;
    onError?: (err: unknown) => void;
  }): { render(container: HTMLElement): Promise<void>; close(): Promise<void>; isEligible(): boolean };
}

let sdk: Promise<PayPalButtonsApi> | null = null;

/** Loads PayPal's script once (it must come from paypal.com, not the bundle),
 *  with the client id the backend uses and the packages' currency. */
export function loadPayPal(currency: string, language: "english" | "hebrew"): Promise<PayPalButtonsApi> {
  sdk ??= (async () => {
    const { data } = await httpsCallable<object, { clientId: string }>(functions, "getPayPalWebConfig")({});
    const params = new URLSearchParams({
      "client-id": data.clientId,
      currency: currencyCode(currency),
      components: "buttons",
      intent: "capture",
      commit: "true",
      locale: language === "hebrew" ? "he_IL" : "en_US",
    });
    await new Promise<void>((resolve, reject) => {
      const script = document.createElement("script");
      script.src = `https://www.paypal.com/sdk/js?${params}`;
      script.dataset.namespace = "paypal_sdk";
      script.onload = () => resolve();
      script.onerror = () => reject(new Error("PayPal script failed to load"));
      document.head.appendChild(script);
    });
    const api = (window as unknown as { paypal_sdk?: PayPalButtonsApi }).paypal_sdk;
    if (!api) throw new Error("PayPal script loaded without its API");
    return api;
  })().catch((e) => {
    sdk = null;
    throw e;
  });
  return sdk;
}

/** createOrder: a checkout for the package, paid through PayPal. */
export async function startPayPalOrder(packageId: string): Promise<{ orderId: string; checkoutId: string }> {
  const { data } = await httpsCallable<object, { orderId?: string; checkoutId?: string }>(functions, "createCheckoutSession")({
    pricingOptionId: packageId,
    platform: "web",
    webReturnUrl: webReturnUrl(),
  });
  if (!data.orderId || !data.checkoutId) throw new Error("no PayPal order");
  return { orderId: data.orderId, checkoutId: data.checkoutId };
}

/** onApprove: the backend captures the order and credits the minutes. */
export async function capturePayPal(checkoutId: string, orderId: string): Promise<void> {
  await httpsCallable(functions, "capturePayPalOrder")({ checkoutId, orderId });
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
