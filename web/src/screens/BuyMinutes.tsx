import { useCallback, useEffect, useRef, useState } from "react";
import { useStrings } from "../i18n";
import { fetchPackages, formatPrice, startCheckout, watchCheckout, type MinutesPackage } from "../services/purchase";

type Load = { kind: "loading" } | { kind: "failed" } | { kind: "ready"; packages: MinutesPackage[] };
type Checkout =
  | { kind: "idle" }
  | { kind: "opening"; pkg: MinutesPackage }
  | { kind: "waiting"; pkg: MinutesPackage; url: string; blocked: boolean }
  | { kind: "done"; minutes: number }
  | { kind: "cancelled" }
  | { kind: "failed" };

/** Minute packages and the card checkout (MinutesPurchaseView). */
export function BuyMinutes({ remainingMinutes }: { remainingMinutes: number }) {
  const { t, language } = useStrings();
  const locale = language === "hebrew" ? "he-IL" : "en-US";
  const [load, setLoad] = useState<Load>({ kind: "loading" });
  const [checkout, setCheckout] = useState<Checkout>({ kind: "idle" });
  const stopWatching = useRef<(() => void) | null>(null);

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

  const buy = async (pkg: MinutesPackage) => {
    // Opened on the click itself, so the browser does not treat it as a popup;
    // it is pointed at the payment page once the checkout exists.
    const tab = window.open("", "_blank");
    setCheckout({ kind: "opening", pkg });
    try {
      const { url, checkoutId } = await startCheckout(pkg.id);
      if (tab) tab.location.href = url;
      setCheckout({ kind: "waiting", pkg, url, blocked: !tab });
      stopWatching.current?.();
      if (checkoutId) {
        stopWatching.current = watchCheckout(checkoutId, (state) => {
          if (state === "pending") return;
          stopWatching.current?.();
          stopWatching.current = null;
          setCheckout(state === "completed" ? { kind: "done", minutes: pkg.minutes } : { kind: "cancelled" });
        });
      }
    } catch (e) {
      console.error("[buy] checkout failed", e);
      tab?.close();
      setCheckout({ kind: "failed" });
    }
  };

  // A checkout left unpaid in its tab does not block starting another.
  const busy = checkout.kind === "opening";
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
      <p className="muted">{t.buySubtitle}</p>

      {checkout.kind !== "idle" && (
        <div className={checkout.kind === "done" ? "notice ok" : checkout.kind === "failed" ? "notice bad" : "notice"} role="status">
          {checkout.kind === "opening" && t.checkoutOpening}
          {checkout.kind === "waiting" && (
            <>
              <span>{checkout.blocked ? t.popupBlocked : t.checkoutWaiting}</span>
              <a className="link" href={checkout.url} target="_blank" rel="noreferrer">
                {t.checkoutReopen}
              </a>
            </>
          )}
          {checkout.kind === "done" && t.checkoutDone(checkout.minutes)}
          {checkout.kind === "cancelled" && t.checkoutCancelled}
          {checkout.kind === "failed" && t.checkoutFailed}
        </div>
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
                <button className="primary" onClick={() => void buy(p)} disabled={busy}>
                  {t.buy}
                </button>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
