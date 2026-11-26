import { useEffect, useRef, useState } from "react";
import type { User } from "firebase/auth";
import { FirebaseError } from "firebase/app";
import { useStrings } from "../i18n";
import {
  claimEmailReward,
  hasUnverifiedEmail,
  publishNotice,
  refreshVerification,
  sendVerificationEmail,
  type AccountRole,
  type EmailReward,
} from "../services/account";

/** EmailRewardBanner: while the address is unverified and a welcome reward is
 *  on offer, says what verifying earns and offers a new link; a teacher whose
 *  bonus is running sees how much of it is left. Claims the reward whenever a
 *  home screen opens, as the apps do, so a Google user, or one who followed
 *  the link in another tab, is credited here. */
export function EmailBanner({ user, role }: { user: User; role: AccountRole }) {
  const { t } = useStrings();
  const [reward, setReward] = useState<EmailReward | null>(null);
  const [sending, setSending] = useState(false);
  const [message, setMessage] = useState<{ ok: boolean; text: string } | null>(null);
  const unverified = hasUnverifiedEmail(user);
  const wasUnverified = useRef(unverified);

  // On opening, and again once the address turns verified.
  useEffect(() => {
    let live = true;
    claimEmailReward().then(
      (r) => {
        if (!live) return;
        setReward(r);
        if (r.status === "granted" || (wasUnverified.current && !unverified && r.status === "already_granted")) {
          publishNotice({ kind: "emailVerified", minutesAdded: role === "student" ? r.minutesAdded : 0 });
        }
        wasUnverified.current = unverified;
      },
      (e) => console.error("[emailBanner] claim failed", e),
    );
    return () => {
      live = false;
    };
  }, [unverified, role]);

  // The link is opened in another tab or on the phone: look again on return.
  useEffect(() => {
    if (!unverified) return;
    const check = () => void refreshVerification().catch((e) => console.error("[emailBanner] reload failed", e));
    window.addEventListener("focus", check);
    return () => window.removeEventListener("focus", check);
  }, [unverified]);

  const resend = async () => {
    setSending(true);
    setMessage(null);
    try {
      await sendVerificationEmail(role);
      setMessage({ ok: true, text: `${t.emailSentTitle}. ${t.newLinkSent(user.email ?? "")}` });
    } catch (e) {
      console.error("[emailBanner] resend failed", e);
      const limited = e instanceof FirebaseError && e.code === "functions/resource-exhausted";
      setMessage({ ok: false, text: limited ? t.tooManyEmails : t.couldntSendEmail });
    } finally {
      setSending(false);
    }
  };

  if (!reward) return null;

  const offer =
    reward.status !== "not_verified"
      ? null
      : role === "student"
        ? reward.studentMinutes > 0 && reward.studentSlotsRemaining > 0
          ? t.studentRewardOffer(reward.studentMinutes)
          : null
        : reward.teacherBonusMinutes > 0
          ? t.teacherRewardOffer(reward.teacherSharePercent, reward.teacherBonusMinutes)
          : null;

  if (unverified && offer) {
    return (
      <section className="card banner verify-banner">
        <span className="banner-icon" aria-hidden>
          ✉
        </span>
        <div className="banner-body">
          <strong>{t.verifyEmailTitle}</strong>
          <span className="muted small">{offer}</span>
          <span className="muted small">{t.verifyLinkHint}</span>
          {message && <span className={message.ok ? "success small" : "error small"}>{message.text}</span>}
          <div className="banner-actions">
            <button className="primary" onClick={resend} disabled={sending}>
              {t.resendEmail}
            </button>
            <button className="secondary" onClick={() => void refreshVerification()}>
              {t.iVerified}
            </button>
          </div>
        </div>
      </section>
    );
  }

  const bonusRunning =
    role === "teacher" && (reward.status === "granted" || reward.status === "already_granted") && reward.teacherBonusMinutesRemaining > 0;
  if (bonusRunning) {
    return (
      <section className="card banner bonus-banner">
        <span className="banner-icon" aria-hidden>
          🎁
        </span>
        <div className="banner-body">
          <strong>{t.teacherBonusTitle}</strong>
          <span className="muted small">{t.teacherBonusText(reward.teacherSharePercent, reward.teacherBonusMinutesRemaining)}</span>
        </div>
      </section>
    );
  }
  return null;
}
