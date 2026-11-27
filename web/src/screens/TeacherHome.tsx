import { useCallback, useEffect, useRef, useState } from "react";
import { useStrings } from "../i18n";
import { onBeforeSignOut, type StudentProfile } from "../services/account";
import { auth } from "../services/firebase";
import { formatPrice } from "../services/purchase";
import {
  acceptInvite,
  declineInvite,
  fetchTeacherDetails,
  goOnline,
  publishSubjects,
  watchInvites,
  watchPresence,
  type Invite,
  type TeacherDetails,
} from "../services/teacher";
import { Lesson } from "./Lesson";

type Current = { questionId: string; conversationType: string; liveKitToken?: string; questionText: string } | null;

/** A short two-note chime for a new question, made on the spot. */
function chime(ctx: AudioContext | null) {
  if (!ctx) return;
  const now = ctx.currentTime;
  [880, 1320].forEach((freq, i) => {
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.0001, now + i * 0.18);
    gain.gain.exponentialRampToValueAtTime(0.25, now + i * 0.18 + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + i * 0.18 + 0.25);
    osc.connect(gain).connect(ctx.destination);
    osc.start(now + i * 0.18);
    osc.stop(now + i * 0.18 + 0.3);
  });
}

/** The teacher's dashboard home (TeacherDashboardView): going online, the
 *  questions offered while online, and the lesson once one is accepted. */
export function TeacherHome({ profile }: { profile: StudentProfile | null }) {
  const { t, language } = useStrings();
  const locale = language === "hebrew" ? "he-IL" : "en-US";
  const uid = auth.currentUser?.uid ?? "";
  const [details, setDetails] = useState<TeacherDetails | null>(null);
  const [wantOnline, setWantOnline] = useState(false);
  const [presence, setPresence] = useState({ online: false, busy: false });
  const [invites, setInvites] = useState<Invite[]>([]);
  const [now, setNow] = useState(Date.now());
  const [busyId, setBusyId] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [current, setCurrent] = useState<Current>(null);
  const stopOnline = useRef<(() => Promise<void>) | null>(null);
  const audio = useRef<AudioContext | null>(null);
  const seen = useRef(new Set<string>());

  useEffect(() => {
    if (!uid) return;
    return watchPresence(uid, setPresence);
  }, [uid]);
  // Again whenever the subjects change (Profile → Edit subjects), so going
  // online publishes the new ones.
  const subjectsKey = JSON.stringify(profile?.subjectSelections ?? {});
  useEffect(() => {
    if (!uid) return;
    fetchTeacherDetails(uid).then(setDetails, (e) => console.error("[teacher] details failed", e));
  }, [uid, subjectsKey]);

  const setOnline = useCallback(
    async (on: boolean) => {
      if (on && !stopOnline.current) {
        // The click is the gesture browsers want before a page may play sound.
        audio.current ??= new AudioContext();
        void audio.current.resume();
        stopOnline.current = goOnline(uid, details?.subjectKeys ?? []);
        setWantOnline(true);
      } else if (!on && stopOnline.current) {
        const stop = stopOnline.current;
        stopOnline.current = null;
        setWantOnline(false);
        await stop().catch((e) => console.error("[teacher] going offline failed", e));
      }
    },
    [uid, details],
  );

  // Subjects edited while online go into presence straight away.
  const publishedKeys = useRef<string | null>(null);
  useEffect(() => {
    const keys = JSON.stringify(details?.subjectKeys ?? []);
    if (wantOnline && details && publishedKeys.current !== null && publishedKeys.current !== keys) {
      void publishSubjects(uid, details.subjectKeys).catch((e) => console.error("[teacher] subjects publish failed", e));
    }
    publishedKeys.current = wantOnline ? keys : null;
  }, [details, wantOnline, uid]);

  // Offline before signing out, and when the page goes away with this tab.
  useEffect(() => {
    const off = onBeforeSignOut(() => setOnline(false));
    return () => {
      off();
    };
  }, [setOnline]);
  useEffect(() => () => void stopOnline.current?.(), []);

  // Offers arrive only while online.
  useEffect(() => {
    if (!wantOnline || !uid) {
      setInvites([]);
      return;
    }
    return watchInvites(uid, (list) => {
      const fresh = list.filter((i) => !seen.current.has(i.questionId));
      fresh.forEach((i) => seen.current.add(i.questionId));
      if (fresh.length) chime(audio.current);
      setInvites(list);
    });
  }, [wantOnline, uid]);

  // The countdown, and a tab title that says a question is waiting.
  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(timer);
  }, []);
  useEffect(() => {
    const base = t.appName;
    document.title = invites.length && !current ? `(${invites.length}) ${t.newQuestion} · ${base}` : base;
    return () => {
      document.title = base;
    };
  }, [invites.length, current, t]);

  const accept = async (invite: Invite) => {
    setBusyId(invite.questionId);
    setNotice(null);
    try {
      const { liveKitToken } = await acceptInvite(invite.questionId);
      setCurrent({ questionId: invite.questionId, conversationType: invite.conversationType, liveKitToken, questionText: invite.text });
    } catch (e) {
      console.error("[teacher] accept failed", e);
      setNotice(t.inviteGone);
    } finally {
      setBusyId(null);
    }
  };

  const decline = async (invite: Invite) => {
    setBusyId(invite.questionId);
    try {
      await declineInvite(invite.questionId);
    } catch (e) {
      console.error("[teacher] decline failed", e);
    } finally {
      setInvites((list) => list.filter((i) => i.questionId !== invite.questionId));
      setBusyId(null);
    }
  };

  if (current) {
    return (
      <div className="narrow">
        <Lesson key={current.questionId} input={{ ...current, role: "teacher" }} onFinished={() => setCurrent(null)} />
      </div>
    );
  }

  const keys = details?.subjectKeys ?? [];
  const status = !wantOnline ? t.statusOffline : presence.busy ? t.statusBusy : presence.online ? t.statusOnline : t.connecting;

  return (
    <section className="page">
      <h2 className="page-title">{t.hello(profile?.fullName?.split(" ")[0] ?? "")}</h2>

      <div className={wantOnline ? "card availability on" : "card availability"}>
        <div className="availability-row">
          <div>
            <strong>{t.availabilityTitle}</strong>
            <div className="muted small">
              <span className={wantOnline && presence.online ? "status-dot live" : "status-dot"} /> {status}
            </div>
          </div>
          <button
            role="switch"
            aria-checked={wantOnline}
            aria-label={t.availabilityTitle}
            className={wantOnline ? "switch on" : "switch"}
            onClick={() => void setOnline(!wantOnline)}
            // Not before the subjects are known: dispatch matches on them.
            disabled={!details}
          >
            <span />
          </button>
        </div>
        <p className="muted small">{wantOnline ? t.onlineHint : t.offlineHint}</p>
        <div className="chips">
          {keys.length ? (
            keys.map((k) => (
              <span key={k} className="chip static">
                {t.topics[k as keyof typeof t.topics] ?? k}
              </span>
            ))
          ) : (
            <span className="muted small">{t.noSubjects}</span>
          )}
        </div>
        {details && !details.verified && <p className="muted small">{t.pendingVerification}</p>}
      </div>

      {notice && (
        <div className="notice bad" role="status">
          {notice}
        </div>
      )}

      {wantOnline && (
        <>
          <h3 className="section-title">{t.incomingQuestions}</h3>
          {invites.length === 0 ? (
            <div className="card center waiting">
              <div className="pulse small-pulse" aria-hidden />
              <p className="muted">{t.waitingForQuestions}</p>
            </div>
          ) : (
            <ul className="invite-list">
              {invites.map((invite) => {
                const left = Math.max(0, Math.ceil((invite.expiresAt - now) / 1000));
                return (
                  <li key={invite.questionId} className="card invite">
                    <div className="invite-head">
                      <span className="chip static">{t.topics[invite.topic as keyof typeof t.topics] ?? invite.topic}</span>
                      <span className="chip static">{t.mediums[invite.conversationType] ?? invite.conversationType}</span>
                      {invite.pricePerMinuteCents > 0 && (
                        <span className="muted small">{t.perMinute(formatPrice(invite.pricePerMinuteCents, "ILS", locale))}</span>
                      )}
                      <span className="toolbar-gap" />
                      {invite.expiresAt > 0 && <span className={left <= 10 ? "countdown urgent" : "countdown"}>{left}s</span>}
                    </div>
                    {invite.studentName && <div className="muted small">{invite.studentName}</div>}
                    <p dir="auto" className="invite-text">
                      {invite.text}
                    </p>
                    {invite.photoUrls.length > 0 && (
                      <div className="attachment-row">
                        {invite.photoUrls.map((u) => (
                          <a key={u} className="attachment" href={u} target="_blank" rel="noreferrer">
                            <img src={u} alt="" />
                          </a>
                        ))}
                      </div>
                    )}
                    <div className="invite-actions">
                      <button className="secondary" onClick={() => void decline(invite)} disabled={busyId !== null}>
                        {t.decline}
                      </button>
                      <button className="primary" onClick={() => void accept(invite)} disabled={busyId !== null}>
                        {busyId === invite.questionId ? t.connecting : t.acceptQuestion}
                      </button>
                    </div>
                  </li>
                );
              })}
            </ul>
          )}
        </>
      )}
    </section>
  );
}
