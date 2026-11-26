import { fetchAndActivate, getRemoteConfig, getValue, type RemoteConfig } from "firebase/remote-config";
import { app, usingEmulators } from "./firebase";

/** The free minutes a new student account earns, as the student app reads
 *  them from Remote Config (StudentIntroViewModel.promotionText,
 *  StudentHomeViewModeling.signUpRewardMinutes): those for signing up and
 *  those for verifying the address, each with the app's default when the
 *  template has no usable value. */
export interface Promotion {
  /** Sign-up plus verification minutes; 0 when neither is on offer. */
  minutes: number;
  /** How many more students get them, or null when there is no limit. */
  slots: number | null;
}

let config: Promise<RemoteConfig | null> | null = null;

/** The app's Remote Config, fetched once; null when it cannot be read (the
 *  emulators have none). */
function remoteConfig(): Promise<RemoteConfig | null> {
  config ??= (async () => {
    if (usingEmulators) return null;
    const rc = getRemoteConfig(app);
    rc.settings.minimumFetchIntervalMillis = 3_600_000;
    await fetchAndActivate(rc);
    return rc;
  })().catch((e) => {
    console.warn("[remoteConfig] unavailable", e);
    return null;
  });
  return config;
}

/** A Remote Config flag; `fallback` when the key is missing or Remote Config
 *  cannot be read. */
export async function fetchFlag(key: string, fallback: boolean): Promise<boolean> {
  const rc = await remoteConfig();
  if (!rc) return fallback;
  const value = getValue(rc, key);
  return value.getSource() === "static" ? fallback : value.asBoolean();
}

/** Null when Remote Config cannot be read: then nothing is promised, rather
 *  than a number the backend may not honour. */
export async function fetchPromotion(): Promise<Promotion | null> {
  const rc = await remoteConfig();
  if (!rc) return null;
  const count = (key: string, fallback: number) => {
    const n = Number(getValue(rc, key).asString());
    return getValue(rc, key).getSource() === "static" || !Number.isFinite(n) ? fallback : Math.max(0, Math.floor(n));
  };
  let signup = count("signup_reward_student_minutes", 0);
  let signupSlots: number | null = count("signup_reward_student_slots", 100);
  if (signup === 0 || signupSlots === 0) [signup, signupSlots] = [0, null];
  let verify = count("email_reward_student_minutes", 60);
  let verifySlots: number | null = count("email_reward_student_slots", 100);
  if (verify === 0 || verifySlots === 0) [verify, verifySlots] = [0, null];
  const slots = [signupSlots, verifySlots].filter((s): s is number => s !== null);
  return { minutes: signup + verify, slots: slots.length ? Math.min(...slots) : null };
}
