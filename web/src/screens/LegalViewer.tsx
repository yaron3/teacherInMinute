import { createContext, useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { useStrings } from "../i18n";
import { legalUrls } from "../config/legal";

export type LegalPage = "eula" | "privacy";

const LegalContext = createContext<(page: LegalPage) => void>(() => {});

/** Opens a legal page in the in-page viewer. */
export const useOpenLegal = () => useContext(LegalContext);

/** Shows the Terms of Service and Privacy Policy inside the app, in a sheet
 *  with the site's page in a frame, as the apps do (AboutWebView), instead of
 *  sending the reader to another tab. */
export function LegalProvider({ children }: { children: ReactNode }) {
  const { t, language } = useStrings();
  const [page, setPage] = useState<LegalPage | null>(null);
  const [loaded, setLoaded] = useState(false);
  const closeButton = useRef<HTMLButtonElement>(null);
  const opener = useRef<HTMLElement | null>(null);

  const open = (p: LegalPage) => {
    opener.current = document.activeElement as HTMLElement | null;
    setLoaded(false);
    setPage(p);
  };
  const close = () => {
    setPage(null);
    opener.current?.focus();
  };

  useEffect(() => {
    if (!page) return;
    closeButton.current?.focus();
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && close();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [page]);

  const url = page ? legalUrls(language)[page] : "";
  const title = page === "eula" ? t.termsOfService : t.privacyPolicy;

  return (
    <LegalContext.Provider value={open}>
      {children}
      {page && (
        <div className="scrim legal-scrim" onClick={close}>
          <div className="legal-sheet" role="dialog" aria-modal="true" aria-label={title} onClick={(e) => e.stopPropagation()}>
            <header>
              <h3>{title}</h3>
              <button ref={closeButton} className="sheet-close" onClick={close} aria-label={t.close} title={t.close}>
                ✕
              </button>
            </header>
            <div className="legal-frame">
              {!loaded && <div className="pulse small-pulse" aria-hidden />}
              <iframe key={url} src={url} title={title} onLoad={() => setLoaded(true)} />
            </div>
          </div>
        </div>
      )}
    </LegalContext.Provider>
  );
}

/** A link-styled button that opens a legal page in the viewer. */
export function LegalLink({ page, children, className }: { page: LegalPage; children: ReactNode; className?: string }) {
  const open = useOpenLegal();
  return (
    <button type="button" className={className ? `legal-link ${className}` : "legal-link"} onClick={() => open(page)}>
      {children}
    </button>
  );
}
