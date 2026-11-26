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

## On the Firebase Hosting site, at /app/

The web client is served from the same Hosting site as the existing pages
(`backend/Firebase/public`), at `/app/`. `firebase deploy --only hosting`
builds it first (the hosting `predeploy` step runs
`scripts/build-hosting.mjs`), with the config of the project being deployed:

| Project | Config | App |
|---|---|---|
| `teacher-in-a-moment-staging` | `.env.staging` | `https://teacher-in-a-moment-staging.web.app/app/` |
| `teacher-in-a-moment` | `.env.prod` (not created yet) | left out until then |

A project with no config deploys the site without `/app/`, so production
site deploys carry on as before. The build goes to `public/app/`, which git
ignores. `firebase.json` adds the `/app/**` rewrite, `no-cache` on the app's
pages and offline-cache files, and long caching for its hashed assets. The
app's install manifest and offline cache cover only `/app/`.

To deploy staging (from `backend/Firebase`):

```bash
npx firebase deploy --only hosting -P staging
```

To build and look at it locally first:

```bash
npm --prefix web run build:staging
```

then start the `hosting-staging` launch configuration (Hosting on
http://localhost:8793, talking to the real staging project).

For production: register a Web app in `teacher-in-a-moment`, put its config in
`web/.env.prod` (as `.env.staging`), and deploy with `-P prod`.

### Staging test accounts

Created by the UI test run on staging (`teacher-in-a-moment-staging`); the
password was generated for the run and is not kept in the repository.

| Role | Email | Name | Notes |
|---|---|---|---|
| Student | `ui-student-11261348@example.com` | UI Test Student | got the sign-up minutes (60) |
| Teacher | `ui-teacher-11261348@example.com` | UI Test Teacher | subjects: Math → trigonometry; offline |

A new student account is credited sign-up minutes within seconds, while the
page can still show 0, so check the balance on the server before asking a
question, and read `onlineTeachers` first: with fewer than three teachers on
a topic, dispatch sends a question to every online teacher.

## Against a real project

Register a Web app in the Firebase project and fill the `VITE_FIREBASE_*`
values in `.env.local` with `VITE_USE_EMULATORS=false`. Add the hosting domain
to Auth's authorized domains. Read the dispatch warning in the root
`CLAUDE.md` before asking a question against production.

## What it does today

- The way in follows the apps (`StudentIntroView`, `LoginView`,
  `CreateAccountView`, `CompleteProfileView`, `UserService.resumeRoute`):
  - A student lands on the intro and can **Get started** without an account
    (anonymous auth, `role: "student"`, `isAnonymous: true`). Asking, buying
    minutes or the profile then offer **Create a user account**, which links
    the email or Google account to the same uid (so the question being
    written stays), or **Log In**, after which the anonymous account is
    deleted through `deleteAnonymousAccount`. Flipping `isAnonymous` to false
    is what `onStudentSignup` watches for.
  - Sign-up is email, password, confirm password and the Terms; then the
    verification email (`sendVerificationEmail`) and "Your account is ready"
    with the offer from `claimEmailReward`. Log in has **Forgot Password?**
    (Firebase's reset email, in the app's language). Auth errors read as the
    apps word them, in English and Hebrew.
  - **Google** sign-in by popup. **Apple** is built but hidden: neither
    project has an Apple Services ID for the web, so set
    `VITE_APPLE_SIGN_IN=true` only once that is configured in Firebase. There
    is no redirect fallback: the site (`web.app`) and the auth domain
    (`firebaseapp.com`) differ, and partitioned browsers lose a redirect's
    result; a blocked popup says to allow pop-ups.
  - Onboarding is resumed from what the profile has, as `resumeRoute` does:
    no role yet → onboarding as the side chosen on the sign-in form. A
    student completes name, optional phone and grade; a teacher chooses
    subjects, then name and phone. Saving the profile saves the role.
  - Home shows the verify-your-email banner (Resend, I've verified; the page
    also re-checks when it regains focus) while a reward is on offer, and
    claims the reward whenever it opens, so a Google account or a link
    followed elsewhere is credited.
  - Left out on purpose: the teacher app's payout-method choice (the app
    keeps it only on the phone, and the web has no payout-details form), the
    permissions step (the browser asks on first use), the "send me
    updates" box (the app only logs it to analytics), and the profile
    step's email field that lets a student with an unverified address
    correct it (`sendVerificationEmail` with a new `email`).
  - Log Out asks first, as the apps' settings do. A failed profile read
    shows a retry rather than onboarding, which could overwrite the role.
- A dashboard: a side menu on a wide screen and a tab bar on a narrow one,
  with the minutes balance always in view. The page is in the URL hash
  (`#lessons`, `#buy`, `#profile`), so the back button works.
- My lessons: every lesson in `users/{uid}.questions` (HistoryModel), with
  lessons, minutes and teachers added up. A lesson opens the same details as
  the app's `LessonDetailView`: who, when and how long, the cost (or, for a
  teacher, the earnings), the medium and rating, the original question with
  its photos, a summary, and the whole chat as it happened, read from the
  `messages` the backend archives on the question when the lesson settles
  (board snapshots and photos show as images). A student can report or
  block the teacher there (`reportTeacher`, which emails support, and
  `blockTeacher`).
- Buy minutes: the active packages in `pricing`, then `createCheckoutSession`
  with `credit_card`, which opens the hosted Tranzila card page in a sheet
  inside the app (an iframe, `allow="payment"`; same origin as the app on
  Hosting, since the page is served through its `/tranzilaCheckout` rewrite).
  The page follows `paymentCheckouts/{id}` and the balance, which the backend
  credits once the payment is confirmed. In the emulators the checkout cannot
  open (no Tranzila or PayPal keys), and the page says so.
  - The checkout carries `webReturnUrl` (`/app/payment-return.html`), so the
    payment pages end there instead of at the app's
    `teacherminute://payment-return` link, which a browser cannot open. The
    backend keeps it only for this project's own Hosting origins (localhost
    under the emulators). In the sheet, that page posts the outcome to the
    app, which closes the sheet; opened on its own, it hands the outcome to
    the app's return screen. Firestore's `paymentCheckouts/{id}` closes the
    sheet too, so a backend without `webReturnUrl` still works.
  - Payment methods, as the apps offer them (`PaymentMethod`): the
    browser's own wallet — Apple Pay in Safari (`ApplePaySession`), Google
    Pay elsewhere — then PayPal and credit card; the choice is remembered.
    Card, Apple Pay (`createApplePayCheckout`) and Google Pay
    (`createGooglePayCheckout`) open the Tranzila page in the sheet. The
    wallets have that page only while the functions' `TRANZILA_WALLETS`
    lists them (`apple_pay,google_pay`); otherwise the backend answers for
    Braintree's native sheet and the web says the wallet is not available.
    PayPal is PayPal's standard checkout: its own buttons (JS SDK, loaded
    from paypal.com with the client id from `getPayPalWebConfig`) in each
    package. `createOrder` opens the checkout through `createCheckoutSession`
    with no method, which returns the PayPal `orderId` and `checkoutId`;
    PayPal runs the approval in its popup; `onApprove` calls
    `capturePayPalOrder`, which captures the checkout's own order (never one
    the page names), checks the amount and credits the minutes — the same
    code as the app's `paypalSuccess` redirect.
- Profile: name, phone, grade and date of birth, saved with the same fields
  and formats as `ProfileViewModel.persistProfileEdits`.
- Help & Support: the contact form (title up to 50, description up to 1,024,
  up to 3 images), previewed before it is sent, as `HelpSupportView`. Images
  are re-encoded as JPEG at up to 2,400 px and uploaded to
  `contactAttachments/{uid}/{id}/{0-2}.jpg`, then `contactRequests/{id}` is
  written; its creation emails support. The emulators' mail is real (see
  `functions/.env`), so don't submit test requests against them.
- Ask: topic, text, chat/voice/video, through `createQuestion`.
- Follows `questions/{qid}` in RTDB (as `QuestionStatusStore` does) to show
  searching → teacher found / no teacher / cancelled. Cancel uses `cancelQuestion`.
- Live lesson, full screen and laid out like the iPad app: the original
  question pinned above the chat, a bottom bar with the media menu, both
  participants and the session clock. In a window 900 px or wider the chat
  sits beside the board, with a handle to drag (or arrow keys; double-click
  resets) whose width is remembered; narrower, they are Chat and Board tabs. It speaks the apps'
  protocol (`ChatSessionService`):
  - `startLesson` join, then ready once connected; `lessonPresence/{qid}/student`
    with disconnect handlers; ending by either side (`leftAt` + `endLesson`).
  - Chat in `questions/{qid}/messages`.
  - Voice and video through `livekit-client`, falling back to chat if media
    fails. Mid-lesson switching through `conversationType`: the student can
    switch any time; when the teacher drops media the student follows at once,
    and when the teacher adds media the student is asked (staying writes
    `mediaPending/student`). Mic and camera toggles publish `mediaState/student`.
  - The whiteboard (`questions/{qid}/board`, 2000 × 2000 logical): pen, line,
    triangle, circle, rectangle and eraser (own strokes only). Drawing needs the
    teacher's leave (`boardPermission`), which lasts 60 seconds from the last
    stroke, as on the apps.
  - Session time from `startedAt`, a warning in the last minute of credit and a
    notice when it runs out (`minutesDeadlineAt`).
- Rating the teacher after a lesson that started (`rateTeacher`).
- Terms of Service and Privacy Policy links on the sign-in page, in the side
  menu and on Help & Support. They open in a sheet over the app with the
  site's page in a frame (`_he` in Hebrew), as the apps' `AboutWebView` does;
  Escape or the close button returns to where the reader was.
  The URLs are fixed in `src/config/legal.ts` for now; the apps read them
  from Remote Config (`eula_url`, `privacy_policy`).
- Teachers. The sign-in form has a Student / Teacher choice; an account of
  the other role is refused with a message. A new teacher chooses subjects
  first, as the app's onboarding requires (`subjectSelections` by area,
  lowercase subtopic keys), then name and phone (normalized as the app does). The catalogue is
  Remote Config's today (Math: algebra, geometry, trigonometry, calculus),
  fixed in `services/teacher.ts`. Identity documents are skipped, as the app
  skips them while `teacher_identity_onboarding` is off.
  A teacher's dashboard has Teach, My lessons, Earnings, Profile and Help:
  - Teach: the availability switch writes `teachers/{uid}` as
    `TeacherPresenceService` does (`availability`, `status`, `subjects` from
    `subjectSelections`, and a server-stamped `lastSeenAt` every minute). A
    web tab cannot be pushed to, so it also takes itself offline on
    disconnect, and on sign-out. Offers from `teacherInvites/{uid}` show with
    a countdown and a chime; Accept and Decline call `acceptInvite` and
    `declineInvite`.
  - The lesson is the same screen from the teacher's side: they draw
    without asking, erase anything, clear the board, and answer a student's
    ask to draw. No rating at the end.
  - My lessons and Earnings both come from `teacherEarningsSummary`: lessons
    with earnings and the student's rating, the total, the next payout and
    each month. Profile shows the subjects, with Edit subjects; an online
    teacher's new subjects go into their presence straight away.
- English and Hebrew (RTL), with the choice saved under
  `settings.language.preference`.

### Testing a lesson without a second device

`scripts/fake-teacher.mjs` plays the teacher against the emulators (it refuses
any project not named `demo-*`). Ask a question in the web app, then:

```bash
node web/scripts/fake-teacher.mjs
```

It waits for a searching question (up to 2 minutes), accepts it, joins,
reports ready and says hello. Then, during the lesson:

```bash
node web/scripts/fake-teacher.mjs draw          # a triangle on the board
node web/scripts/fake-teacher.mjs grant         # or decline: answer an ask to draw
node web/scripts/fake-teacher.mjs media video   # or audio / text
node web/scripts/fake-teacher.mjs state 1       # 1 = mic muted, 2 = camera off
node web/scripts/fake-teacher.mjs say "Hello"
node web/scripts/fake-teacher.mjs leave
```

### Testing the teacher side

`scripts/fake-student.mjs` is the other way round. Sign in as a teacher, go
online, then:

```bash
node web/scripts/fake-student.mjs ask algebra text   # waits for you to accept
node web/scripts/fake-student.mjs askdraw            # ask to draw
node web/scripts/fake-student.mjs draw               # a circle on the board
node web/scripts/fake-student.mjs media audio        # or video / text
node web/scripts/fake-student.mjs say "Thanks!"
node web/scripts/fake-student.mjs leave
```

Emulator teacher account: `web-test-teacher@example.com` / `webtest123`,
"Web Test Teacher", subjects Math → algebra, geometry (gone when the
emulators restart).

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

1. Photos in chat, the math keyboard, zooming the board on small screens,
   topping up when credit runs out mid-lesson, and retrying `endLesson` after
   a dropped connection.
2. Strings, and the legal page URLs, from the Remote Config template the apps
   use, instead of `i18n.ts` and `config/legal.ts`.
3. A profile photo (upload to Storage), and deleting the account.
4. Google and Apple sign-in (they need OAuth web clients and authorized domains).
5. Web push (FCM with a VAPID key), then the teacher side.
6. A production Web app config (`.env.prod`), and a link to `/app/` from the
   site's home page.
