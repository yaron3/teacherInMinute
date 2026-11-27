import { useCallback, useEffect, useRef, useState } from "react";
import { useStrings } from "../i18n";
import { fetchFlag } from "../services/promotion";
import { GooglePayCancelled, chargeGooglePay, googlePayButton, prepareGooglePay, requestGooglePayNonce } from "../services/googlepay";
import {
  WalletUnavailableError,
  availablePayMethods,
  fetchPackages,
  formatPrice,
  capturePayPal,
  loadPayPal,
  startPayPalOrder,
  startCheckout,
  watchCheckout,
  watchPaymentReturn,
  type MinutesPackage,
  type PayMethod,
} from "../services/purchase";

type Load = { kind: "loading" } | { kind: "failed" } | { kind: "ready"; packages: MinutesPackage[] };
type Checkout =
  | { kind: "idle" }
  | { kind: "opening"; pkg: MinutesPackage }
  | { kind: "paying"; pkg: MinutesPackage; url: string; checkoutId: string }
  /** PayPal's popup is open for this package. */
  | { kind: "paypal"; pkg: MinutesPackage }
  | { kind: "confirming" }
  | { kind: "done"; minutes: number }
  | { kind: "cancelled" }
  | { kind: "failed"; unavailable?: PayMethod };

/** Minute packages and the checkout (MinutesPurchaseView with
 *  PaymentMethodSheet): the browser's own wallet, PayPal or a card. */
export function BuyMinutes({ remainingMinutes }: { remainingMinutes: number }) {
  const { t, language } = useStrings();
  const locale = language === "hebrew" ? "he-IL" : "en-US";
  const [load, setLoad] = useState<Load>({ kind: "loading" });
  const [checkout, setCheckout] = useState<Checkout>({ kind: "idle" });
  const stopWatching = useRef<(() => void) | null>(null);
  // Google Pay waits for Remote Config (`enable_google_pay`, off when unset),
  // as in the apps.
  const [methods, setMethods] = useState(() => availablePayMethods(false));
  useEffect(() => {
    void fetchFlag("enable_google_pay", false).then((on) => setMethods(availablePayMethods(on)));
  }, []);
  const [chosen, setChosen] = useState<PayMethod | null>(() => localStorage.getItem("buy.payMethod") as PayMethod | null);
  const method: PayMethod = chosen && methods.includes(chosen) ? chosen : methods[0];
  const chooseMethod = (m: PayMethod) => {
    setChosen(m);
    localStorage.setItem("buy.payMethod", m);
  };

  const reload = useCallback(async () => {
    setLoad({ kind: "loading" });
    try {
      setLoad({ kind: "ready", packages: await fetchPackages(language === "hebrew" ? "he" : "en") });
    } catch (e) {
      console.error("[buy] packages load failed", e);
      setLoad({ kind: "failed" });
    }
  }, [language]);

  useEffect(() => {
    void reload();
  }, [reload]);
  useEffect(() => () => stopWatching.current?.(), []);

  const finish = useCallback((next: Checkout) => {
    stopWatching.current?.();
    stopWatching.current = null;
    setCheckout(next);
  }, []);

  // The payment pages end on payment-return.html, in the sheet or in PayPal's
  // window, which says how it went; Firestore says the same once the backend
  // has credited it.
  useEffect(
    () =>
      watchPaymentReturn((outcome) =>
        setCheckout((c) => {
          if (c.kind !== "paying" && c.kind !== "paypal") return c;
          if (outcome === "cancelled") return { kind: "cancelled" };
          // Success is announced by the checkout itself, with the minutes.
          return { kind: "confirming" };
        }),
      ),
    [],
  );

  const follow = (pkg: MinutesPackage, checkoutId: string) => {
    stopWatching.current?.();
    stopWatching.current = watchCheckout(checkoutId, (state) => {
      if (state === "pending") return;
      finish(state === "completed" ? { kind: "done", minutes: pkg.minutes } : { kind: "cancelled" });
    });
  };

  const buy = async (pkg: MinutesPackage) => {
    const chosen = method;
    setCheckout({ kind: "opening", pkg });
    try {
      const { url, checkoutId } = await startCheckout(pkg.id, chosen);
      setCheckout({ kind: "paying", pkg, url, checkoutId });
      if (checkoutId) follow(pkg, checkoutId);
    } catch (e) {
      console.error("[buy] checkout failed", e);
      setCheckout({ kind: "failed", unavailable: e instanceof WalletUnavailableError ? chosen : undefined });
    }
  };

  // PayPal's buttons run the checkout themselves; these follow along.
  const paypal = {
    createOrder: async (pkg: MinutesPackage) => {
      const { orderId, checkoutId } = await startPayPalOrder(pkg.id);
      setCheckout({ kind: "paypal", pkg });
      follow(pkg, checkoutId);
      return { orderId, checkoutId };
    },
    approved: () => setCheckout({ kind: "confirming" }),
    done: (pkg: MinutesPackage) => finish({ kind: "done", minutes: pkg.minutes }),
    cancelled: () => finish({ kind: "cancelled" }),
    failed: () => finish({ kind: "failed" }),
  };

  const busy = checkout.kind === "opening" || checkout.kind === "paying" || checkout.kind === "paypal";
  const lowestPerMinute =
    load.kind === "ready" && load.packages.length
      ? Math.min(...load.packages.map((p) => p.priceCents / p.minutes))
      : 0;

  return (
    <section className="page">
      <h2 className="page-title">{t.buyTitle}</h2>
      <div className="balance">
        <span className="muted">{t.minutesBalance}</span>
        <strong>{remainingMinutes}</strong>
      </div>
      <p className="muted">{t.buySubtitleAll}</p>

      <div className="pay-methods" role="radiogroup" aria-label={t.choosePaymentMethod}>
        <span className="label">{t.choosePaymentMethod}</span>
        <div className="chips">
          {methods.map((m) => (
            <button
              key={m}
              type="button"
              role="radio"
              aria-checked={method === m}
              className={method === m ? "chip selected pay-method" : "chip pay-method"}
              lang="en"
              onClick={() => chooseMethod(m)}
            >
              <span aria-hidden className="pay-mark">
                {PAY_MARK[m]}
              </span>
              {t.payMethodNames[m]}
            </button>
          ))}
        </div>
      </div>

      {checkout.kind !== "idle" && checkout.kind !== "paying" && (
        <div className={checkout.kind === "done" ? "notice ok" : checkout.kind === "failed" ? "notice bad" : "notice"} role="status">
          {checkout.kind === "opening" && t.checkoutOpening}
          {checkout.kind === "paypal" && t.paypalWaiting}
          {checkout.kind === "confirming" && t.checkoutConfirming}
          {checkout.kind === "done" && t.checkoutDone(checkout.minutes)}
          {checkout.kind === "cancelled" && t.checkoutCancelled}
          {checkout.kind === "failed" && (checkout.unavailable ? t.walletUnavailable(t.payMethodNames[checkout.unavailable]) : t.checkoutFailed)}
        </div>
      )}

      {checkout.kind === "paying" && (
        <CheckoutSheet
          url={checkout.url}
          title={`${t.checkoutTitle} · ${checkout.pkg.name}`}
          // Closing leaves the checkout unpaid; Firestore still reports it if
          // it was paid a moment before.
          onClose={() => setCheckout({ kind: "idle" })}
        />
      )}

      {load.kind === "loading" && <div className="pulse small-pulse" />}
      {load.kind === "failed" && (
        <div className="card center">
          <p>{t.loadFailed}</p>
          <button className="secondary" onClick={reload}>
            {t.retry}
          </button>
        </div>
      )}
      {load.kind === "ready" && load.packages.length === 0 && (
        <div className="card center">
          <p className="muted">{t.noPackages}</p>
        </div>
      )}
      {load.kind === "ready" && load.packages.length > 0 && (
        <div className="packages">
          {load.packages.map((p) => {
            const best = load.packages.length > 1 && p.priceCents / p.minutes === lowestPerMinute;
            return (
              <div key={p.id} className={p.highlighted ? "package highlighted" : "package"}>
                {(p.highlighted || best) && <span className="badge">{best ? t.bestValue : t.mostPopular}</span>}
                <h3>{p.name}</h3>
                <div className="package-minutes">{t.minutesShort(p.minutes)}</div>
                {p.description && <p className="muted small">{p.description}</p>}
                <div className="package-price">{formatPrice(p.priceCents, p.currency, locale)}</div>
                <div className="muted small">{t.perMinute(formatPrice(Math.round(p.priceCents / p.minutes), p.currency, locale))}</div>
                {method === "paypal" ? (
                  <PayPalButtons pkg={p} disabled={busy} flow={paypal} />
                ) : method === "google_pay" ? (
                  <GooglePayButton pkg={p} disabled={busy} flow={paypal} />
                ) : (
                  <button className="primary" onClick={() => void buy(p)} disabled={busy}>
                    {t.buyWith(t.payMethodNames[method])}
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}

/** PayPal's own buttons for one package (JS SDK standard checkout): the
 *  buyer approves in PayPal's popup, then the backend captures the order. */
function PayPalButtons({
  pkg,
  disabled,
  flow,
}: {
  pkg: MinutesPackage;
  disabled: boolean;
  flow: {
    createOrder: (pkg: MinutesPackage) => Promise<{ orderId: string; checkoutId: string }>;
    approved: () => void;
    done: (pkg: MinutesPackage) => void;
    cancelled: () => void;
    failed: () => void;
  };
}) {
  const { t, language } = useStrings();
  const container = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<"loading" | "ready" | "unavailable">("loading");
  // The latest handlers, without re-rendering PayPal's buttons for each.
  const handlers = useRef(flow);
  handlers.current = flow;

  useEffect(() => {
    let closed = false;
    let buttons: { close(): Promise<void> } | null = null;
    let checkoutId = "";
    loadPayPal(pkg.currency, language)
      .then((paypal) => {
        if (closed || !container.current) return;
        const rendered = paypal.Buttons({
          style: { layout: "horizontal", color: "gold", shape: "rect", label: "paypal", tagline: false, height: 40 },
          createOrder: async () => {
            const order = await handlers.current.createOrder(pkg);
            checkoutId = order.checkoutId;
            return order.orderId;
          },
          onApprove: async ({ orderID }) => {
            handlers.current.approved();
            try {
              await capturePayPal(checkoutId, orderID);
              handlers.current.done(pkg);
            } catch (e) {
              console.error("[buy] PayPal capture failed", e);
              handlers.current.failed();
            }
          },
          onCancel: () => handlers.current.cancelled(),
          onError: (e) => {
            console.error("[buy] PayPal error", e);
            handlers.current.failed();
          },
        });
        if (!rendered.isEligible()) {
          setState("unavailable");
          return;
        }
        buttons = rendered;
        return rendered.render(container.current).then(() => !closed && setState("ready"));
      })
      .catch((e) => {
        console.error("[buy] PayPal unavailable", e);
        if (!closed) setState("unavailable");
      });
    return () => {
      closed = true;
      void buttons?.close().catch(() => undefined);
    };
  }, [pkg, language]);

  return (
    <div className={disabled ? "paypal-slot busy" : "paypal-slot"}>
      {state === "loading" && <div className="pulse small-pulse" aria-hidden />}
      {state === "unavailable" && <p className="error small">{t.walletUnavailable(t.payMethodNames.paypal)}</p>}
      <div ref={container} />
    </div>
  );
}

/** Google's own Google Pay button for one package (Google Pay API for the
 *  web, Braintree as the gateway). The sheet opens straight from the tap at
 *  the package's price; the checkout is opened and charged once the buyer
 *  approves, for the checkout's own price. */
function GooglePayButton({
  pkg,
  disabled,
  flow,
}: {
  pkg: MinutesPackage;
  disabled: boolean;
  flow: { approved: () => void; done: (pkg: MinutesPackage) => void; cancelled: () => void; failed: () => void };
}) {
  const { t, language } = useStrings();
  const container = useRef<HTMLDivElement>(null);
  const [state, setState] = useState<"loading" | "ready" | "unavailable">("loading");
  const handlers = useRef(flow);
  handlers.current = flow;

  useEffect(() => {
    let closed = false;
    void prepareGooglePay(pkg.currency).then((pay) => {
      if (closed || !container.current) return;
      if (!pay) return setState("unavailable");
      const onClick = () => {
        // loadPaymentData runs inside requestGooglePayNonce before any await,
        // so the sheet opens from the tap itself.
        requestGooglePayNonce(pay, { cents: pkg.priceCents, currency: pkg.currency })
          .then(async (nonce) => {
            handlers.current.approved();
            await chargeGooglePay(pkg.id, nonce);
            handlers.current.done(pkg);
          })
          .catch((e) => {
            if (e instanceof GooglePayCancelled) return handlers.current.cancelled();
            console.error("[buy] Google Pay failed", e);
            handlers.current.failed();
          });
      };
      container.current.replaceChildren(googlePayButton(pay, onClick, language));
      setState("ready");
    });
    return () => {
      closed = true;
    };
  }, [pkg, language]);

  return (
    <div className={disabled ? "wallet-slot busy" : "wallet-slot"}>
      {state === "loading" && <div className="pulse small-pulse" aria-hidden />}
      {state === "unavailable" && <p className="error small">{t.walletUnavailable(t.payMethodNames.google_pay)}</p>}
      <div ref={container} className="gpay-button" />
    </div>
  );
}

const PAY_MARK: Record<PayMethod, string> = { apple_pay: "", google_pay: "G", paypal: "P", card: "💳" };

/** The payment page inside the app (the card page, or with Apple Pay or
 *  Google Pay on it), in a sheet like the legal pages. Same origin as the app,
 *  so `allow="payment"` lets the browser's wallet open from it. */
function CheckoutSheet({ url, title, onClose }: { url: string; title: string; onClose: () => void }) {
  const { t } = useStrings();
  const [loaded, setLoaded] = useState(false);
  const closeButton = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    closeButton.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  return (
    <div className="scrim legal-scrim">
      <div className="legal-sheet checkout-sheet" role="dialog" aria-modal="true" aria-label={title}>
        <header>
          <h3>{title}</h3>
          <button ref={closeButton} className="sheet-close" onClick={onClose} aria-label={t.close} title={t.close}>
            ✕
          </button>
        </header>
        <div className="legal-frame">
          {!loaded && <div className="pulse small-pulse" aria-hidden />}
          <iframe src={url} title={title} allow="payment" onLoad={() => setLoaded(true)} />
        </div>
      </div>
    </div>
  );
}
