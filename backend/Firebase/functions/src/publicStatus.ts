/**
 * The public, read-only status page (public/status.html) behind the Hosting
 * rewrite /api/status. Kept apart from ./liveStatus so the admin module, which
 * reads the same status, does not load an HTTP endpoint.
 */

import { logger } from "firebase-functions";
import { onRequest } from "firebase-functions/v2/https";
import { LiveStatus, StatusCheck, readLiveStatus } from "./liveStatus";

/** What the public status page (public/status.html) may see: the states and
 *  the counts, never the details, which name internal tools and remedies. */
export type PublicLiveStatus = Omit<LiveStatus, "checks"> & {
  checks: Array<Pick<StatusCheck, "id" | "label" | "state">>;
};

export function toPublicLiveStatus(status: LiveStatus): PublicLiveStatus {
  return {
    ...status,
    checks: status.checks.map(({ id, label, state }) => ({ id, label, state })),
  };
}

/** How long Hosting's CDN may serve one answer, so however many people watch
 *  the status page, the database is read about twice a minute. */
export const PUBLIC_STATUS_CACHE_SECONDS = 30;

/**
 * GET /api/status (a Hosting rewrite), read-only and unauthenticated. A failed
 * read answers 503 and is never cached, so the page shows the outage at once.
 */
export const publicLiveStatus = onRequest(async (req, res) => {
  if (req.method !== "GET") {
    res.set("Allow", "GET").status(405).send("Method Not Allowed");
    return;
  }
  try {
    const status = toPublicLiveStatus(await readLiveStatus(Date.now()));
    res.set("Cache-Control", `public, max-age=${PUBLIC_STATUS_CACHE_SECONDS}, s-maxage=${PUBLIC_STATUS_CACHE_SECONDS}`);
    res.json(status);
  } catch (err) {
    logger.error("[liveStatus] public status read failed", err);
    res.set("Cache-Control", "no-store").status(503).json({ error: "unavailable" });
  }
});
