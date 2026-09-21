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
3. Register an **iOS app** with bundle id `com.yaronj.tim` and download
   `GoogleService-Info.plist`.
4. Register an **Android app** with package `com.yaronj.tim` and download
   `google-services.json`.

The same bundle id and package are deliberate: the two builds never coexist on
one device, and keeping them equal means nothing else in the project has to
know which environment it is.

## 2. Drop the two files in

| File | Goes to |
| --- | --- |
| `GoogleService-Info.plist` (staging) | `teacher-minute/Darwin/GoogleService-Info-Staging.plist` |
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
  `GoogleService-Info.plist` with the staging one when `$CONFIGURATION` is
  `Debug` and that file exists. Until the file exists the phase is a no-op, so
  the build keeps working.
- **Android** — the Google Services plugin prefers
  `src/debug/google-services.json` over `app/google-services.json`. Nothing in
  `build.gradle.kts` selects it; see the README in that directory for why this
  is not done with product flavors.

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
