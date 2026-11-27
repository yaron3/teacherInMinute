import { useEffect, useState } from "react";
import { useStrings } from "../i18n";
import { publishNotice, watchNotice, type Notice } from "../services/account";

/** The notes that follow an account across screens: "Your account is ready"
 *  after signing up (CreateAccountView's success dialog), and "Email
 *  verified" when the welcome reward lands. */
export function Notices() {
  const { t } = useStrings();
  const [notice, setNotice] = useState<Notice | null>(null);
  useEffect(() => watchNotice(setNotice), []);
  if (!notice) return null;

  let title: string;
  let lines: string[];
  if (notice.kind === "accountReady") {
    const { offer, role } = notice;
    const reward =
      offer?.status === "not_verified" || offer?.status === "granted"
        ? role === "student"
          ? offer.studentMinutes > 0 && offer.studentSlotsRemaining > 0
            ? t.studentRewardOffer(offer.studentMinutes)
            : null
          : offer.teacherBonusMinutes > 0
            ? t.teacherRewardOffer(offer.teacherSharePercent, offer.teacherBonusMinutes)
            : null
        : null;
    title = t.accountReadyTitle;
    lines = [t.verificationSent(notice.email), ...(reward ? [reward] : [])];
  } else {
    title = t.emailVerifiedTitle;
    lines = [notice.minutesAdded > 0 ? t.freeMinutesAdded(notice.minutesAdded) : t.thanksVerifying];
  }

  return (
    <div className="scrim" onClick={() => publishNotice(null)}>
      <div className="dialog" role="alertdialog" aria-modal="true" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <h3>{title}</h3>
        {lines.map((line) => (
          <p key={line} className="muted">
            {line}
          </p>
        ))}
        <div className="dialog-actions">
          <button className="primary" autoFocus onClick={() => publishNotice(null)}>
            {t.ok}
          </button>
        </div>
      </div>
    </div>
  );
}
