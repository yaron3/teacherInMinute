# Tasks

## 1. Save photo on Android (student) not working — DONE (alpha warning pending)
- Affects both cases (camera capture and gallery pick).
- Should save the image in the chat summary.
- Should also prompt the user to ask if they want to save the image to the device gallery.
- TODO: iOS still logs `writeImageAtIndex:1094: ⭕️ ERROR: 'TeacherMinute' is trying to save an opaque image (2160x2160) with 'AlphaPremulLast'`. Tried `UIImage(data: jpegData)`, `UIGraphicsImageRenderer` with `format.opaque = true`, and `PHPhotoLibrary` with raw JPEG bytes — warning still appears. Investigate whether it originates from `ImageRenderer`'s intermediate UIImage or somewhere else.

## 2. "Find teacher" button does not look disabled on Android — DONE
- The disabled state styling is not visible on Android.
- Ensure the disabled visual state matches the iOS appearance.
- Also apply the same disabled visual state to the chat send button when there is no text to send.

## 3. Show "No teacher available" message to student — DONE
- When no teacher is available, the student should see a clear "No teacher available" message instead of waiting indefinitely.

## 4. Badge on Chat / Board is too small — DONE
- Increase the badge size so it is easily readable.
- make tab title background red

## 5. Show spinner when navigating to the Lessons tab — DONE
- While the Lessons tab is loading, display a spinner until the content is ready.

## 6. Tapping a specific lesson on Android shows nothing - DONE
- Tapping a lesson row on Android does not open the lesson details.
- Should navigate to the lesson detail screen (matching iOS behavior).
- Fix: switched `.sheet(isPresented:)` (with optional `if let` inside) to `.sheet(item:)` driven by `selectedLesson`, which is Skip/Android-compatible.

## 7. Allow sending an image as a question — DONE
- Add the ability for a student to send an image as part of a question.
- The teacher should be able to see the image when receiving the question.

## 8. Show spinner when transitioning from video chat to text chat — DONE
- After a video chat ends and the user is moved to text chat, show a spinner blocking input until everything is ready and the user can type.
- Implementation: `ChatSessionView` now tracks `isTransitioningToText`; when the student picks "Continue with text only" from the connection setup timeout, a spinner overlay replaces the setup view until the text session reports it's connected.

## 9. Disable back on Android — DONE
- disable the option to use system back from the main tab to the onboarding phase
- Implementation: `MainActivity` registers an `OnBackPressedCallback` that, when enabled, calls `moveTaskToBack(true)` instead of letting the system back unwind to onboarding. `MainTabView` enables/disables the callback via `AndroidBackNavigationBridge` in `onAppear`/`onDisappear`, so nested NavigationStacks inside tabs keep their normal back behavior.

## 10. Verify invite pushes reach a teacher whose app is not running — TO VERIFY
- Since the keep-alive (PR #22), a teacher whose app has stopped sending keep-alives stays available for as long as `teachers/{uid}/fcmToken` holds a push token, and questions reach them only by push. Nothing has confirmed yet that the push arrives.
- Android: go online, then background or kill the app, and have a student ask on a topic only this teacher covers (see "Never send a demo question to a real teacher" in the root `CLAUDE.md`). Expect a notification from `AndroidIncomingQuestionNotifier`; tapping it opens the app with the invite on the dashboard, and the notification clears when the invite expires (90 s). Use a real device: the Android 14 emulator used before received no FCM at all (root `bugs.md`).
- iOS: expected to fail today. The invite push is data-only, with no `aps` alert, so iOS shows nothing. The push needs an alert first; then run the same check as Android.
- Dead token: uninstall the app while online. Once FCM rejects the token as unregistered, the next invite sent to this teacher drops `fcmToken`, and the keep-alive watchdog takes them offline within about a minute. FCM can take a while to notice an uninstall.
- Afterwards, turn the toggle off: closing the app no longer takes a teacher with a push token offline.

## 11. Firebase setup for Instant Teacher (`com.yaronj.student`) — TO DO
- Upload the APNs authentication key to the Instant Teacher iOS app (Firebase console → Project settings → Cloud Messaging). The key belongs to the Apple team, so the one Pro Teacher (`com.yaronj.tim`) already uses will do. Until then, students on iPhone get no push notifications.
- Add the SHA-1 and SHA-256 fingerprints of the debug and upload keys to the Instant Teacher Android app, and the Play App Signing key's once the Play listing exists, then download `google-services.json` again. Google sign-in on Android fails without them (`ApiException` 10): the current file has no Android OAuth client for `com.yaronj.student`.
- Delete the `com.yaronj.teacher` iOS and Android apps registered by mistake. Nothing uses them since Pro Teacher went back to `com.yaronj.tim`.

## 12. Store listings — TO DO
- App Store Connect: create Instant Teacher with bundle id `com.yaronj.student`. Its App ID needs Push Notifications, Sign in with Apple and Apple Pay (`merchant.com.yaronj.tim`), as in `Darwin/Entitlements.plist`. Rename the existing `com.yaronj.tim` listing to Pro Teacher. App Store names must be unique, so if that listing is still called Instant Teacher, rename it first.
- Google Play Console: create Instant Teacher (`com.yaronj.student`) and rename the existing `com.yaronj.tim` listing to Pro Teacher.
- Add Instant Teacher's Play App Signing SHA-256 to the `com.yaronj.student` entry in `backend/Firebase/public/.well-known/assetlinks.json` and deploy hosting (`firebase deploy --only hosting`), so PayPal's return link opens the app.

## 13. Remote Config for the two apps — TO DO
- Once Instant Teacher is on the App Store, set the `iOS` value of `student_app_url` in `backend/Firebase/remote_config_tim.json` to its App Store link (`https://apps.apple.com/app/id…`). The Google Play link is already the default.
- Deploy the template from `backend/Firebase`: `firebase deploy --only remoteconfig`.
- Release Instant Teacher in both stores before the Pro Teacher update, and deploy the template before that update ships (a device keeps its fetched config for up to an hour). Otherwise the dialog sends students to an app they cannot find.

## 14. Report and block a student in Pro Teacher — TO DO
- Instant Teacher lets a student report and block a teacher (App Store Guideline 1.2). Pro Teacher has the same user-generated content (chat, photos, board, voice and video) but no way for a teacher to report or block a student, so its next App Review may ask for one.
- Backend: mirror `backend/Firebase/functions/src/moderation.ts` for the teacher side. A teacher reports a student of one of their lessons (the question's `acceptedByTeacher` is the caller). A block is stored on the teacher, and dispatch must never invite that teacher to that student's questions — the reverse of `QuestionDoc.blockedTeachers`.
- App: reuse `ReportTeacherView` and its view model with the copy and calls for a student, from the teacher's lesson (flag next to End), `TeacherLessonHistoryView`'s lesson detail, and Settings → Privacy Controls (blocked students, with Unblock).
