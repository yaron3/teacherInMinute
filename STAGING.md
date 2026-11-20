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

## 2. Drop the files in

Everything Firebase-specific lives under `teacher-minute/Config/`, one folder
per project:

| File | Goes to |
| --- | --- |
| Instant Teacher's `GoogleService-Info.plist` | `Config/<project>/InstantTeacher/GoogleService-Info.plist` |
| Pro Teacher's `GoogleService-Info.plist` | `Config/<project>/ProTeacher/GoogleService-Info.plist` |
| `google-services.json` (lists both packages) | `Config/<project>/google-services.json` |

`<project>` is `Prod` or `Staging`. Commit them. Firebase config files are not
secrets — they ship inside the app — and the team needs the same targets.

When a project gives an app a Google sign-in client, set that target's
`TIM_GOOGLE_URL_SCHEME_<project>` build setting (`TIM_GOOGLE_URL_SCHEME_Staging`
for staging) to the plist's `REVERSED_CLIENT_ID`. The build fails until they
match.

## 3. Seed it

- Deploy the backend to it: `cd backend && firebase deploy -P staging`
  (rules, functions and the Remote Config template — see below for the alias).
- Create the four demo accounts from `CLAUDE.md`, password `123456`.
- Remote Config needs the localization template or every string falls back to
  English: `firebase deploy --only remoteconfig -P staging`.

## How the switch works

`teacher-minute/Config/Environment.xcconfig` picks the project per build
configuration, for both platforms:

```
TIM_FIREBASE_ENV_DEBUG = Staging
TIM_FIREBASE_ENV_RELEASE = Prod
```

- **iOS** — `Darwin/TeacherMinute.xcconfig` includes that file and sets
  `TIM_FIREBASE_ENV` from it. The "Select the Firebase config" build phase
  copies `Config/$TIM_FIREBASE_ENV/$PRODUCT_NAME/GoogleService-Info.plist` into
  the app, and fails the build when the file is missing or was registered for a
  different bundle id. `TIM_GOOGLE_URL_SCHEME` follows the project too.
- **Android** — `app/build.gradle.kts` reads the same two lines and copies
  `Config/<project>/google-services.json` to `src/debug/` and `src/release/`
  (gitignored), where the Google Services plugin looks first. See the README
  in `src/debug/` for why staging is not a product flavor.

To build one configuration against the other project without editing the
file: `xcodebuild … TIM_FIREBASE_ENV=Prod`, or `./gradlew … -PtimFirebaseEnv=Prod`.
Xcode's "Run skip gradle" phase passes its `TIM_FIREBASE_ENV` on to gradle, so
an Xcode build and the Android build it launches always use the same project.

Both builds log which config they took: `Firebase config: Staging (<project id>)`
in the Xcode build log, `Firebase config (debug): Staging` in the gradle output.

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
