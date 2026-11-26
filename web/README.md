# Teacher in a Minute — web client (Windows via PWA)

A browser client for the same Firebase backend the iOS and Android apps use.
Edge or Chrome on Windows installs it as an app (its own window and Start-menu
entry) through the PWA manifest. It runs on Mac and Linux the same way.

Stack: Vite + React + TypeScript, the Firebase JS SDK, and `vite-plugin-pwa`.

## Run locally against the emulators

The Firebase CLI needs Java 21 or later:

```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
```

```bash
npm --prefix backend/Firebase/functions run emulators:app
```

```bash
cp web/.env.example web/.env.local
```

```bash
npm --prefix web run dev
```

Open http://localhost:5180. The orange corner tag means the app is talking to
the emulators (project `demo-teacher-in-a-moment`, which never reaches a real
project).

A new emulator student starts with 0 minutes. To credit some:

```bash
curl -X PATCH -H 'Authorization: Bearer owner' -H 'Content-Type: application/json' \
  "http://127.0.0.1:8085/v1/projects/demo-teacher-in-a-moment/databases/(default)/documents/users/<uid>?updateMask.fieldPaths=remainingMinutes" \
  -d '{"fields":{"remainingMinutes":{"integerValue":"30"}}}'
```

Emulator test account created while building this (emulator only, gone when
the emulators restart): student `web-test-student@example.com` / `webtest123`,
display name "Web Test Student".

## Against a real project

Register a Web app in the Firebase project and fill the `VITE_FIREBASE_*`
values in `.env.local` with `VITE_USE_EMULATORS=false`. Add the hosting domain
to Auth's authorized domains. Read the dispatch warning in the root
`CLAUDE.md` before asking a question against production.

## What it does today

- Email/password sign-in and student sign-up. It writes the same `users/{uid}`
  fields as `UserProfile.firestoreData`.
- Live remaining-minutes counter.
- Ask: topic, text, chat/voice/video, through `createQuestion`.
- Follows `questions/{qid}` in RTDB (as `QuestionStatusStore` does) to show
  searching → teacher found / no teacher / cancelled. Cancel uses `cancelQuestion`.
- Live lesson, speaking the apps' protocol (`ChatSessionService`):
  `startLesson` join, then ready once connected; `lessonPresence/{qid}/student`
  with disconnect handlers; chat in `questions/{qid}/messages`; voice and video
  through `livekit-client`, falling back to chat if media fails; ending by
  either side (`leftAt` stamp + `endLesson`).
- Rating the teacher after a lesson that started (`rateTeacher`).
- English and Hebrew (RTL), with the choice saved under
  `settings.language.preference`.

### Testing a lesson without a second device

`scripts/fake-teacher.mjs` plays the teacher against the emulators (it refuses
any project not named `demo-*`). Ask a question in the web app, then:

```bash
node web/scripts/fake-teacher.mjs
```

It accepts the newest searching question, joins, reports ready and says hello.
To have the teacher leave:

```bash
node web/scripts/fake-teacher.mjs leave
```

By default voice and video don't connect against the emulators: the functions
emulator signs LiveKit tokens with the placeholder key in
`backend/Firebase/functions/.env.demo-teacher-in-a-moment`, which LiveKit Cloud
rejects ("invalid API key"), and the lesson carries on by chat. To test media,
put a LiveKit key for the `teacher-in-a-moment-qx23966i` project (a separate,
revocable dev key, not production's) in `backend/Firebase/functions/.env.local`,
which git ignores and the emulator reads last:

```
LIVEKIT_API_KEY=...
LIVEKIT_API_SECRET=...
```

then restart the emulators. The script saves the teacher's own LiveKit token
to the state file it prints, so a second tab can join the room as the teacher.

## Next slices

1. Whiteboard (`questions/{qid}/board`), photos in chat, switching between
   chat, voice and video mid-lesson (`mediaState`/`mediaPending`), the
   minutes-left countdown, and retrying `endLesson` after a dropped connection.
2. Strings from the Remote Config template the apps use, instead of `i18n.ts`.
3. Top-up through the Tranzila browser checkout the hosting rewrites already
   serve.
4. Google and Apple sign-in (they need OAuth web clients and authorized domains).
5. Web push (FCM with a VAPID key), then the teacher side.
6. Hosting: a separate Firebase Hosting site or target, so `public/` (the
   marketing site) stays as it is.
