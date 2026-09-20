import * as admin from "firebase-admin";
import { logger } from "firebase-functions";

// Every readRcNumber used to pull the whole Remote Config template over the
// network — a fresh HTTP round trip per key, so resolvePricingForStudent alone
// fetched it three times and createQuestion paid for one on the ask path. The
// template changes when someone edits it in the console, which is rare next to
// how often these run, so an instance holds it briefly and re-reads after that.
//
// This cache lives here rather than in ./pricing so every caller shares one
// copy: the ask path reads limits (./questionLimits) and prices (./pricing) on
// the same request, and a cache per module would fetch the template twice.
const RC_TEMPLATE_TTL_MS = 60_000;
let rcTemplateCache: { template: admin.remoteConfig.RemoteConfigTemplate; fetchedAt: number } | undefined;
let rcTemplateInFlight: Promise<admin.remoteConfig.RemoteConfigTemplate> | undefined;

async function getRcTemplate(): Promise<admin.remoteConfig.RemoteConfigTemplate> {
  if (rcTemplateCache && Date.now() - rcTemplateCache.fetchedAt < RC_TEMPLATE_TTL_MS) {
    return rcTemplateCache.template;
  }
  // Concurrent callers share one fetch rather than each starting their own.
  if (!rcTemplateInFlight) {
    rcTemplateInFlight = admin
      .remoteConfig()
      .getTemplate()
      .then((template) => {
        rcTemplateCache = { template, fetchedAt: Date.now() };
        return template;
      })
      .finally(() => {
        rcTemplateInFlight = undefined;
      });
  }
  return rcTemplateInFlight;
}

/** One numeric Remote Config parameter, or `undefined` when it is absent or
 *  unreadable — callers supply their own fallback rather than failing the
 *  request they are serving. */
export async function readRcNumber(key: string): Promise<number | undefined> {
  try {
    const template = await getRcTemplate();
    const param = template.parameters?.[key] as
      | { defaultValue?: { value?: string } }
      | undefined;
    const raw = param?.defaultValue?.value;
    if (raw == null) return undefined;
    const parsed = Number(raw);
    return Number.isFinite(parsed) ? parsed : undefined;
  } catch (error) {
    logger.warn(`[remoteConfig] failed reading Remote Config ${key}`, error);
    return undefined;
  }
}
