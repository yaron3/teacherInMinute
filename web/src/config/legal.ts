import type { Language } from "../i18n";

// The EULA and privacy policy pages. The apps read these from Remote Config
// (`eula_url`, `privacy_policy`, localized); until the web client reads that
// template too, they are fixed here. Hebrew opens the site's `_he` pages, as
// CreateAccountViewModel.legalURL falls back to.
//
// Hosted at /app/ on a project's site, the pages are next door on the same
// site (staging's own pages on staging); run anywhere else, the live site's.
const SITE = import.meta.env.BASE_URL === "/app/" ? "" : "https://teacher-in-a-moment.web.app";

export function legalUrls(language: Language): { eula: string; privacy: string } {
  const suffix = language === "hebrew" ? "_he" : "";
  return {
    eula: `${SITE}/eula${suffix}.html`,
    privacy: `${SITE}/privacypolicy${suffix}.html`,
  };
}
