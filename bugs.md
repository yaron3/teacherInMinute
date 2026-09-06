# Bugs

Found while shooting the Play Store screenshot set on Android (build **1.0.4 (42)**,
Debug) on 2026-09-06, plus what the follow-up work turned up.

Two devices were used, and the difference between them mattered more than once:

- `emulator-34-medium_phone` — Android 14, Google Play image. **Receives no FCM
  at all**, proven with a `notification`-payload push that the system posts
  without app code involved. A cold boot did not restore it. Anything
  push-related has to be tested elsewhere.
- Galaxy S8 (SM-G950F), **Android 9**. Real FCM works. Below API 33, so
  `POST_NOTIFICATIONS` does not exist and notification-denial paths cannot be
  exercised here.

Statuses below reflect where each item stands after the session, not where it
stood when first written.

---

## Production data

### 1. A demo teacher was live in `onlineTeachers` for two days

**Status: stale entry gone. Fix landed in `2a9b891`; still unverified.**

נועה כהן (`Bm4HU3Uv5DSEE8XFLDq5aldYtlH2`), online since 2026-09-04 17:00 UTC,
carrying algebra, trigonometry and geometry. Meanwhile the app itself showed her
as לא זמין and the account was signed out — stale presence, not a live session.
Real students asking those topics were dispatched to a demo account the whole
time. This is the "logging out does not take a teacher offline" defect from
`marketing-screenshots/appstore-flows-dark/README.md`.

The entry cleared on its own once that account signed in again during capture
(the dashboard writes `status: offline` on `configurePresence`), and
`onlineTeachers` is now empty. Nothing was written to RTDB by hand.

**Root cause, corrected.** The first reading — that Android lacked the
`onDisconnect` dead-man's switch — was wrong. It is implemented on both
platforms:

- iOS: `TeacherPresenceService.writeStatus` calls
  `onDisconnectUpdateChildValues(["status": "offline"])`.
- Android: `AndroidTeacherPresenceManager.updateTeacherRecord` calls
  `teacherRef.onDisconnect().updateChildren(...)`.

(`TeacherPresenceService`'s `#if SKIP` branch does lack it, but that branch is
dead code — `configurePresence` takes `#if os(Android)` first and routes to the
Kotlin manager.)

`onDisconnect` only fires when the RTDB socket closes. Signing out left the
process — and the socket — alive, so it never ran, and
`AuthService.signOut()` was nothing but `try Auth.auth().signOut()`.

**Fix applied:** `AuthService.signOut()` now clears presence *before* dropping
the auth session (afterwards there is no uid to write for). **Not yet verified**
— testing it means signing a real device out.

---

## Functional

### 2. Profile never loads

**Status: fixed and verified on-device. Landed in `2a9b891`.**

Tapping Profile sat on "Loading profile…" indefinitely. Reproduced on two
teacher accounts (נירה דוד, `teacher_demo_english` / Sarah Miller) — and, later,
on a student account too (`student_demo_hebrew`), so it was not teacher-specific.

It is **not** a data problem. Instrumented on the phone:

```
[Profile] loading profile
[Profile] summary fetched role=student
[Profile] loaded name=יונתן לוי rows=5 displayable=true
```

The load completed in ~58 ms with `displayable=true`, while the screen still
showed the spinner 18 seconds later.

**Root cause.** Logging `ObjectIdentifier` on both sides showed a single shared
view-model instance, with `body` running exactly once — before the load — and
never again:

```
[Profile] body    vm=0x7e2f266000 name=Profile rows=5 loaded=false
[Profile] loading vm=0x7e2f266000
[Profile] loaded  name=david rows=5 displayable=true
```

So Skip is not recomposing from `@Observable` mutations. `MainTabView` already
carries a comment about the profile "only appearing after switching tabs and
back" — the same symptom, since a tab switch forces a fresh composition that
happens to read current values.

Ruled out along the way: instance identity, `@State` vs `@Bindable` vs a plain
property (none of the three fixed it).

**Fix applied:** `ProfileView` reads a `@State var profileRevision` in `body`
and bumps it after every load path (`.task`, Retry, both editor sheets'
`onDismiss`). A view's own `@State` does reliably invalidate the body. Verified
on the phone: `david` / `a@a.com` / `2222` where it previously rendered
`Profile` / `–` / `–`.

Note: the one-line `UserPhotoStore` addition at `ProfileViewModel.swift:356` is
in the upload path, not the load path, and was never the cause.

> **See #10.** This fix is a workaround for a systemic problem, not a cure.

### 3. The subject picker loses backend-added subtopics

**Status: partly fixed in `17b3cef`; the catalog question is still open.**

Fixed: matching stored subtopics against the catalog was exact, so if the Remote
Config fetch ever failed and the built-in fallback took over — its keys are
capitalised, the stored ones lowercase — every saved subtopic silently unticked
and saving the sheet wrote that empty selection over the teacher's real
subjects. Both sides now reduce to lowercase letters and digits.

Not fixed: Geometry is absent from the published catalog entirely
(`subjects = ["Math"]`, `subTaskMath = ["Algebra","Trigonometry"]`), so the
picker still cannot offer it. Closing that means either expanding the published
catalog or keeping unknown stored subtopics selectable — a product decision, and
expanding it removes a safety margin: Geometry is currently a safe topic for
demo questions *because* no real teacher can select it (see CLAUDE.md on never
sending a demo question to a real teacher).

Original report follows.

Teacher home renders `Math: Algebra, Math: Geometry, Math: Trigonometry`, but
Edit Subjects opens showing "1 subject, 2 subtopics" with only Algebra and
Trigonometry ticked — Geometry absent. Geometry was written backend-side per the
iOS README, so the picker appears not to round-trip subtopics it did not write
itself. Saving from that sheet would silently drop Geometry, which is exactly
the topic the demo lessons rely on.

### 4. Teachers land in ID verification on every cold start

**Status: not a bug — intended, confirmed with the author.**

Every launch goes to "Verify Your Identity — Step 1 of 2" and needs "Continue -
upload later". A teacher who has not uploaded a government ID is meant to be
asked again each time; the skip is the escape hatch, not a workaround. Recorded
here only because it was filed as a defect after being carried over from the iOS
notes.

---

## Localization

### 5. Language switching leaves Remote Config strings cached in the old language

**Status: not a bug — my repro was at fault. Confirmed on device.**

Selecting עברית in Settings → Language switches the whole UI immediately: tab
bar, content and RTL layout, with no relaunch and no "Force Reload Remote
Config".

The mixed UI came from editing `settings.language.preference` in the prefs file
directly, which bypasses `updateLanguage`. That method awaits
`LocalizationManager.updateLanguageCode`, which refetches Remote Config for the
new language, and only then writes the `@AppStorage`-observed key so the locale
flip and the string refresh land in the same render pass. Writing the key by
hand skips the refetch, leaving the previous language's strings cached — exactly
the half-translated screen filed here.

The lesson is about the harness, not the app: driving a setting through its
storage is not the same as driving it through its code path, and only the latter
is what a user does.

### 6. `Computer Science: הכל`

**Status: fixed in `43b33ed`.** Not a localization bug at all — the write path
already stores English keys and the read path localizes. Two teacher profiles
held `Computer_Science: ["הכל"]`, written by an older build; "All" matches no
subtopic in the catalog, so it could not be translated and came out raw. The
orphaned area was dropped from both. A sweep of all 32 teacher profiles now
reports zero Hebrew subtopic values and zero empty areas.

---

## Copy

All three live in `backend/Firebase/remote_config_tim.json` rather than Swift, so
they are a template edit plus a republish.

### 7. "A teacher connects immediate."

**Status: fixed in `4a8a9e4`.** Production was already serving the correct
string; the broken English survived only in this repo's template, which had
drifted. Worth closing on its own — a `firebase deploy --only remoteconfig` from
the repo would have pushed the bad value back over the good one. Verified by
diffing all 661 published parameters against the file: zero differences.

### 8. "1 reviews"

**Status: fixed in `5c2236d`, both languages verified on device.** The rating
card formatted every count through "%d reviews". The singular now has its own
string, matching how `onlineTeachersCountText` and
`LessonFormatting.reviewCountText` already handle it. Renders "1 review" in
English and "ביקורת אחת" in Hebrew.

### 9. Teacher home stat cards show "מתעדכן…" placeholders on cold sign-in

**Status: open (marginal).** The window is wide enough to be captured — three
Hebrew screenshots came out all-placeholder and had to be retaken behind a load
guard. Wide enough that a real user sees it.

---

## Found later

### 10. Skip does not drive recomposition from `@Observable` mutations

**Status: open. Probably the most consequential item here.**

The evidence in #2 is that a view's `body` never re-ran when its `@Observable`
view model changed. That is not specific to `ProfileView`:
`TeacherDashboardView` and `StudentHomeView` may only appear to work because
their data is present by first render, or because their own `@State` forces a
recompose. `MainTabView`'s "only appearing after switching tabs and back" note
points the same way.

Every screen driven by an `@Observable` view model is a candidate. The fix in #2
is a per-view workaround; the general problem is how Skip's observation is
wired, and deserves its own look.

### 11. `AndroidPermissionBridge.hasPermission` aborts the process

**Status: fixed and verified on-device. Landed in `2a9b891`.**

```
Fatal signal 6 (SIGABRT)
Abort message: 'JNI DETECTED ERROR IN APPLICATION: the return type of
CallStaticObjectMethodA does not match boolean
teacher.minute.AndroidPermissionManager.hasPermission(java.lang.String)'
```

`requestPermission` gets correct type inference from its declared `-> Bool`;
`hasPermission` wrapped the call in `(try? … ) ?? false`, which breaks that
chain, so `callStatic` resolved to the *object* JNI variant against a method
returning `boolean`. JNI treats that as fatal and aborts rather than throwing.

It had never fired because **nothing called `hasPermission` at runtime** until
#12 did. Fixed by spelling out the return type inside the closure.

### 12. `PermissionService.notificationStatus()` was a stub on Android

**Status: fixed and verified on-device. Landed in `2a9b891`.**

It returned `.notDetermined` unconditionally, so the profile's notification row
read "Not requested" on every Android device regardless of the real state. Now
queries `POST_NOTIFICATIONS` through the bridge (which already handles API < 33,
where the runtime permission does not exist). The row now reads "Enabled".

Known limit: `checkSelfPermission` answers false both for "denied" and for
"never asked", so an ungranted permission reads as `.denied`.

`captureStatus` (microphone, camera) is **still** a stub returning
`.notDetermined` on Android — untouched, and the same class of bug.

### 13. Android never surfaced incoming questions in the background

**Status: implemented and verified on-device. Landed in `2a9b891`.**

`TeacherMinuteFirebaseMessagingService.onMessageReceived` logged the payload and
dropped it. The backend does send the invite (`sendInvitePush` — high priority,
data-only, TTL-matched), but data-only messages never auto-post a notification,
and on Android invites otherwise arrive via `startAndroidInvitePolling`, which
stops with the app. **A backgrounded Android teacher received nothing at all.**

Added `AndroidIncomingQuestionNotifier`: own high-importance channel, suppressed
while the app is resumed, expires with the invite, id keyed on `questionId`,
cleared on foreground. `ttlSeconds` added to the push payload so the client does
not hardcode a copy of `INVITE_EXPIRY_SECONDS`.

Not done: tapping opens the app but does not route to the invite (the
`questionId` rides along as an intent extra that nothing consumes yet — the
invite poll picks it up on resume). Not a full-screen intent, since
`USE_FULL_SCREEN_INTENT` is restricted to calling and alarm apps from API 34.
Small icon is `android.R.drawable.ic_dialog_info`, a placeholder.

### 14. A teacher with notifications denied stays in the dispatch pool

**Status: implemented in `2a9b891`, not verified.**

Given #13, a backgrounded teacher is only reachable by notification. One who has
not granted them sits in the pool unreachable, and every wave they are picked
for burns its timeout before moving on.

`TeacherDashboardViewModel.enforceNotificationRequirement()` now requests
permission and takes the teacher offline if it is not granted, after every
toggle and on every return to foreground (permission can be revoked in system
settings while the app is away).

Unverified: the only real device available is Android 9, where
`POST_NOTIFICATIONS` does not exist and `hasPermission` returns `true`
unconditionally, so denial cannot be exercised. Needs an API 33+ device.
