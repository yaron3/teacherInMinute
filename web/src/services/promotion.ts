import { fetchAndActivate, getRemoteConfig, getValue } from "firebase/remote-config";
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

let pending: Promise<Promotion | null> | null = null;

/** Null when Remote Config cannot be read (the emulators have none): then
 *  nothing is promised, rather than a number the backend may not honour. */
export function fetchPromotion(): Promise<Promotion | null> {
  pending ??= load().catch((e) => {
    console.warn("[promotion] Remote Config unavailable", e);
    return null;
  });
  return pending;
}

async function load(): Promise<Promotion | null> {
  if (usingEmulators) return null;
  const config = getRemoteConfig(app);
  config.settings.minimumFetchIntervalMillis = 3_600_000;
  await fetchAndActivate(config);
  const count = (key: string, fallback: number) => {
    const n = Number(getValue(config, key).asString());
    return getValue(config, key).getSource() === "static" || !Number.isFinite(n) ? fallback : Math.max(0, Math.floor(n));
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
