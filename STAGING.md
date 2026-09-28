# Staging

A second Firebase project, so the app can be exercised without writing to the
database real lessons run on. Everything below the first section is already in
the repository; the first section is the part only you can do.

## 1. Create the project (Firebase console)

1. Add a project named `teacher-in-a-moment-staging`.
2. Enable **Realtime Database**, **Authentication** (Email/Password and Google),
   **Firestore**, **Storage** and **Remote Config**. The app reads all five at
   launch, and a missing one fails as a permission error rather than something
   that names the cause.
3. Register two **iOS apps**, bundle ids `com.yaronj.student` (Instant
   Teacher) and `com.yaronj.tim` (Pro Teacher), and download each one's
   `GoogleService-Info.plist`.
4. Register two **Android apps** with the same two packages and download
   `google-services.json`, which lists both.

The same bundle ids and packages as production are deliberate: a staging and a
production build of one app never coexist on one device, and keeping them equal
means nothing else in the project has to know which environment it is.

## 2. Drop the two files in

| File | Goes to |
| --- | --- |
| Instant Teacher's `GoogleService-Info.plist` (staging) | `teacher-minute/Darwin/InstantTeacher/GoogleService-Info-Staging.plist` |
| Pro Teacher's `GoogleService-Info.plist` (staging) | `teacher-minute/Darwin/ProTeacher/GoogleService-Info-Staging.plist` |
| `google-services.json` (staging) | `teacher-minute/Android/app/src/debug/google-services.json` |

Commit both. Firebase config files are not secrets — they ship inside the app —
and the team needs the same staging target.

## 3. Seed it

- Deploy the backend to it: `cd backend && firebase deploy -P staging`
  (rules, functions and the Remote Config template — see below for the alias).
- Create the four demo accounts from `CLAUDE.md`, password `123456`.
- Remote Config needs the localization template or every string falls back to
  English: `firebase deploy --only remoteconfig -P staging`.

## How the switch works

**Debug builds use staging, release builds use production.** There is no flag
to set and no scheme to remember.

- **iOS** — the "Select the Firebase config" build phase overwrites the bundled
  `GoogleService-Info.plist` with the staging one from the app's folder when
  `$CONFIGURATION` is `Debug` and that file exists. Until the file exists the
  phase is a no-op, so the build keeps working. Staging gives each app its own
  Google sign-in client, so set the target's `TIM_GOOGLE_URL_SCHEME` for the
  Debug configuration to the staging plist's `REVERSED_CLIENT_ID`; the same
  build phase fails the build until they match.
- **Android** — the Google Services plugin prefers
  `src/debug/google-services.json` over `app/google-services.json`, for both
  flavors. Nothing in `build.gradle.kts` selects it; see the README in that
  directory for why staging is not a product flavor.

Both builds log which config they took, as `Firebase config: staging` in the
Xcode build log and the project id in the Android manifest merger output.

Nothing in the app names a database URL any more. Both platforms take it from
whichever Firebase config they were built with — iOS from `DATABASE_URL` in the
plist, Android from `firebase_url` in `google-services.json`, which is why
`FirebaseDatabase.getInstance()` is called with no argument.

## Deploying

`backend/.firebaserc` has one alias. Add the second once the project exists:

```bash
cd backend
firebase use --add     # pick the staging project, name the alias "staging"
```

Then:

```bash
firebase deploy --only database -P staging     # rules to staging
firebase deploy --only database                # rules to production
```

**Check a rules change against staging before production.** The rules tests in
`backend/Firebase/functions` run against an emulator and cover the logic, but
they cannot tell you the deploy itself succeeds or that the console's own
validation agrees:

```bash
cd backend/Firebase/functions && npm run test:rules
```

## What staging does not protect you from

Dispatch fans a question out to every online teacher matching its topic, and
presence lives in the database — so on staging the only teachers online are
the ones you signed in yourself. That is the point. It does not make the
production warning in `CLAUDE.md` any less true when you are pointed at
production.
