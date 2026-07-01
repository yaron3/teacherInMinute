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
