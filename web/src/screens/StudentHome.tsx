import { useStrings } from "../i18n";
import { TOPICS, type ConversationType } from "../services/questions";
import type { StudentProfile } from "../services/account";
import { useStudentHome } from "./useStudentHome";
import { Lesson } from "./Lesson";

const CONVERSATION_TYPES: ConversationType[] = ["text", "audio", "video"];

export function StudentHome({ profile }: { profile: StudentProfile | null }) {
  const { t } = useStrings();
  const vm = useStudentHome();
  const { search } = vm;

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
        input={{ questionId: search.questionId, conversationType: search.conversationType, liveKitToken: search.liveKitToken }}
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

      <button className="primary" onClick={vm.ask} disabled={!vm.canAsk}>
        {t.findTeacher}
      </button>
    </section>
  );
}
