
Bugs

[x] I agree to privacy policy ... in hebrew doesn't have valid link
    Fixed: the localized markdown was passed to `Text` as a plain String, so the links were never tappable in any language (most noticeable in Hebrew). Now parsed via AttributedString markdown on iOS with the openURL handler, and shown as explicit tappable Terms/Privacy buttons on Android (Skip's Text can't render markdown links). CreateAccountView.swift.
[x] When user signup it shouldn't be back button to signup screen
    Fixed: after signup we `router.replace(with: .chooseRole)` instead of `push`, so the sign-up screen is removed from the navigation stack. CreateAccountView.swift.
[x] In teacher the badge on the profile should not appear for now
    Fixed: removed the Verified/Not Verified pill from the profile header. ProfileView.swift.
[x] teacher get the error: Listen for query at teachers/<uid> failed: Missing or insufficient permissions.
    Fixed: added a `teachers/{uid}` rule to firestore.rules allowing a teacher to read their own record (server-written). backend/Firebase/firestore.rules.
    NOTE: requires deploy — `firebase deploy --only firestore:rules`.
[x] full name should auto capitalized
    Fixed: AuthInputField gained an `autocapitalization` param; the Full Name field now uses `.words`. AuthPrimaryButton.swift, CompleteProfileView.swift.
[x] asking for notification permission should be only after first lesson, with a view describing why, and only then the system request
    Fixed: removed notifications from onboarding permissions; `registerCurrentDevice` no longer prompts (only registers if already granted). After a student's first lesson we show NotificationPermissionExplainerView, and the system prompt appears only if they tap "Enable Notifications". New: NotificationPromptStore.swift, NotificationPermissionExplainerView.swift; edits in PermissionsSetupView(+VM), PushNotificationService, ChatSessionView, StudentHomeView.
[x] when student edits profile he should have a drop down to select the grade
    Fixed: student Grade row in the profile editor is now a Menu/dropdown (Grade 1–12, College, Adult Learner). ProfileView.swift, ProfileViewModel.swift.
[x] in profile the currency should not be here - move to settings, auto ILS, not changeable for now
    Fixed: removed the currency picker from the profile editor; added a Settings → Preferences screen showing Currency = ILS (read-only). SettingsView.swift, SettingsSection.swift, ProfileView.swift.
[x] when student wants to send a question the default should be audio call - add a settings option to change the default
    Fixed: AskTeacherSheet now defaults the session type to the stored preference (audio when unset). Settings → Preferences has a Default Session Type picker (student only). ConversationType.swift, AskTeacherSheet.swift, SettingsView.swift, SettingsSection.swift.
[x] on Android send an image opens a gallery - add option to take a picture as well
    Fixed: sending a photo on Android now shows a chooser (Take Photo / Choose from Library). Camera capture uses ACTION_IMAGE_CAPTURE + FileProvider; camera permission requested first. AndroidImagePickerManager.kt, AndroidManifest.xml, res/xml/file_paths.xml, AskTeacherSheet.swift.
[x] in tab lessons: teacher should see earnings (was always 0); student should see only time consumed
    Fixed: lessons are billed per minute, and question docs often lack an explicit cost, so earnings resolved to 0. Cost is now derived from duration × per-minute price (price_per_minute_<currency>), and teacher earnings from cost × teacher_share. Student lessons tab now shows only time (spend/cost hidden). HistoryModel.swift, SettingsRemoteConfigService.swift, StudentLessonHistoryView.swift.
[x] if student sets in settings to share his image the teacher should see it
    Fixed: the "Show my profile image" preference is now persisted to the user's profile (boolean), and the backend only shares the photo with the other participant when it isn't disabled. SettingsView.swift, UserService.swift, backend/Firebase/functions/src/questions.ts.
    NOTE: backend requires build + deploy — `firebase deploy --only functions`.

Deployment reminders:
- firestore.rules  -> firebase deploy --only firestore:rules
- functions        -> firebase deploy --only functions (rebuild the TS: npm run build)


[x] When user end session there is pop up dialog where he wants to save the board - it should have an option not to save
    Fixed: the save-board dialog now has an explicit "Don't save" button that ends the session without saving the board anywhere (in addition to Save to gallery / Save to chat only). ChatSessionView.swift.
[x] When user tap to end the session it should end imidiatlly the sesion and counting time.
    Fixed: the "Are you sure?" confirmation stays; the moment the user confirms "End session" the timer freezes immediately so time stops counting right away (even if the save-board prompt follows). ChatSessionView.swift (handleEndSessionPrimaryAction .confirmEnd).
[x] when end session the dilalog isn't localized
    Fixed: the end-session/save-board dialog strings were missing Hebrew (only English in Remote Config). Added Hebrew for "Save board to gallery?", the two save prompts, "Save to gallery", "Save to chat only" and the new "Don't save" as local hebrewFallbacks (immediate) plus Remote Config entries. RemoteConfigLocalizationService.swift, backend/Firebase/remote_config_tim.json.
    NOTE: remote_config requires deploy — local fallbacks make it work without one.
[x] when  student asks a question the student name and profile image (if student approve to send) are not show
    Fixed: the incoming-question card hardcoded "Student" + a generic icon, and the invite payload never carried the student's identity. Backend now snapshots studentName + (privacy-respecting) studentImageURL on the question at creation and writes both into the teacherInvites RTDB node (initial wave + backfill); the FCM push uses the real name too. Client reads them through IncomingInvite → InviteService/AndroidInviteManager → TeacherDashboardViewModel and the LiveRequestCard shows the student's name and profile avatar. types.ts, questions.ts, dispatch.ts, AndroidInviteManager.kt, IncomingInvite.swift, InviteService.swift, TeacherDashboardViewModel.swift, TeacherDashboardView.swift.
    NOTE: backend requires build + deploy — `firebase deploy --only functions`. Image only shows when the student has "Show my profile image" enabled.
[x] When treacher accept a question on connect the text not localized
    Fixed: the teacher's connecting overlay passed raw string literals instead of localized strings — `footerText: "Setting up the session"` and the ChatSessionView `title: "Student"`. Both now go through LocalizationSupport.localized() (the Hebrew values already existed in Remote Config). Also added local Hebrew fallbacks for both so they translate even before Remote Config loads. MainTabView.swift, RemoteConfigLocalizationService.swift.
[x] on save to gallery user get: 12.13.0 - [FirebaseDatabase][I-RDB038012] setValue: or removeValue: at /questions/70c636b8-18e3-4088-b2fb-d662b9c18cef/board/viewports/teacher failed: permission_denied
    Fixed: this was a race, not a rules problem. When the session ends the backend finalizes/removes the RTDB questions/{qid} node, but the whiteboard kept emitting viewport updates during the end/save flow — those late writes hit a node that no longer matches the RTDB write rule, so they were rejected. Board writes are now suppressed once the lesson has been reported ended: guarded updateBoardViewport + sendStroke on hasReportedLessonEnd in the shared view model (covers iOS + Android), and the whiteboard's onViewportChanged no longer fires while the session is ending. ChatSessionService.swift, ChatSessionView.swift.
[] in tab lessons: teacher should see earnings (is always 0) - add logs when it calculate the earning per session and the total
[] bedge on lessons tab should be only when adding new lesson and student didn't enter the tab yet
[] the student name should be seen in the detail lesson
[] when teacher sees the incoming question it doesn't show the student name - only after connecting I see the name
[] after some seconds the question disappear from the teacher device - it should stay while the system sends to more teachers.
