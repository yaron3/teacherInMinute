import { useEffect, useState } from "react";
import { useStrings } from "../i18n";
import { fetchPromotion } from "../services/promotion";
import { CreateAccountPrompt } from "./CreateAccount";
import { TOPICS, type ConversationType } from "../services/questions";
import type { StudentProfile } from "../services/account";
import { useStudentHome } from "./useStudentHome";
import { Lesson } from "./Lesson";

const CONVERSATION_TYPES: ConversationType[] = ["text", "audio", "video"];

export function StudentHome({ profile, anonymous = false }: { profile: StudentProfile | null; anonymous?: boolean }) {
  const { t } = useStrings();
  const vm = useStudentHome();
  const { search } = vm;
  // A student without an account has no minutes: asking offers one, with the
  // free minutes it brings (notEnoughMinutesMessage). The question stays.
  const [needsAccount, setNeedsAccount] = useState(false);
  const [rewardMinutes, setRewardMinutes] = useState(0);
  useEffect(() => {
    if (anonymous) void fetchPromotion().then((p) => setRewardMinutes(p?.minutes ?? 0));
    else setNeedsAccount(false);
  }, [anonymous]);
  const ask = () => {
    if (anonymous && (profile?.remainingMinutes ?? 0) < 2) setNeedsAccount(true);
    else void vm.ask();
  };

  if (search.kind === "searching" || search.kind === "sending") {
    return (
      <section className="card center">
        <div className="pulse" aria-hidden />
        <h2>{t.searching}</h2>
        <p className="muted">{t.searchingHint}</p>
        <button className="secondary" onClick={vm.cancel} disabled={search.kind === "sending"}>
          {t.cancel}
        </button>
      </section>
    );
  }

  if (search.kind === "matched") {
    return (
      <Lesson
        key={search.questionId}
        input={{ questionId: search.questionId, conversationType: search.conversationType, liveKitToken: search.liveKitToken, questionText: search.questionText }}
        onFinished={vm.finishLesson}
      />
    );
  }

  if (search.kind !== "idle" && search.kind !== "error") {
    return (
      <section className="card center">
        <h2>{search.kind === "noMatch" ? t.noTeacher : t.cancelled}</h2>
        <button className="primary" onClick={vm.reset}>
          {t.tryAgain}
        </button>
      </section>
    );
  }

  return (
    <section className="card">
      {profile && <p className="pill">{t.minutesLeft(profile.remainingMinutes)}</p>}
      <h2>{t.askTitle}</h2>

      <label className="label">{t.topic}</label>
      <div className="chips">
        {TOPICS.map((topic) => (
          <button
            key={topic}
            className={topic === vm.topic ? "chip selected" : "chip"}
            onClick={() => vm.setTopic(topic)}
          >
            {t.topics[topic]}
          </button>
        ))}
      </div>

      <textarea
        dir="auto"
        value={vm.text}
        onChange={(e) => vm.setText(e.target.value)}
        placeholder={t.questionPlaceholder}
        rows={5}
      />

      <label className="label">{t.howToTalk}</label>
      <div className="chips">
        {CONVERSATION_TYPES.map((type) => (
          <button
            key={type}
            className={type === vm.conversationType ? "chip selected" : "chip"}
            onClick={() => vm.setConversationType(type)}
          >
            {t[type]}
          </button>
        ))}
      </div>

      {search.kind === "error" && (
        <p className="error" role="alert">
          {search.message}
        </p>
      )}

      {needsAccount ? (
        <CreateAccountPrompt message={t.createAccountToSend(rewardMinutes)} />
      ) : (
        <button className="primary" onClick={ask} disabled={!vm.canAsk}>
          {t.findTeacher}
        </button>
      )}
    </section>
  );
}
