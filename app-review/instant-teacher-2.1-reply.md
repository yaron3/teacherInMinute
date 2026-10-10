# Instant Teacher — reply to Guideline 2.1 (Information Needed)

Paste the reply below into App Store Connect, and the same text into
**App Review Information → Notes**. Fill in the `[…]` parts first.

---

Hello App Review team,

Thank you for the review. Here is the information you asked for. This
submission is version 1.0.6 (build 7).

**1. Screen recording**

A screen recording from a physical iPhone running iOS [version] is attached
to this reply. It starts at app launch and shows, in order: the
first-launch tutorial; asking a question and account registration; the
minutes purchase screen; a live lesson with a teacher; rating the teacher;
reporting and blocking the teacher, and unblocking; account deletion; and
logging in.

This build adds an in-app tutorial. It opens at launch and walks through the
whole flow on screenshots of the app: taking a photo of the exercise,
writing a question instead, the live session, its chat and its shared
whiteboard. It has Skip on every page, and a "Don't show me again" check box
on the last page. It can be opened again at any time from the side menu →
Tutorial.

**2. Purpose and target audience**

Instant Teacher connects students with a real human teacher for a short,
on-demand, one-on-one lesson, usually within about 90 seconds.

- **Problem it solves:** a student working on homework or exam prep gets
  stuck on one step. A textbook or an AI answer often doesn't explain where
  their own reasoning went wrong. Booking a regular tutor takes days and costs
  a full lesson.
- **What it offers:** the student photographs or types the question. A
  qualified teacher for that subject joins a live session within about 90
  seconds. The session has chat, a shared whiteboard, and voice or video. It
  lasts only as long as the student needs, and the student pays per minute,
  with no subscription.
- **Audience:** school and university students, and parents paying for their
  children's help. Teachers use a separate app, Pro Teacher. They are verified
  (identity and teaching documents) before they can take lessons.

**3. How to use the main features**

Demo student account (email and password):
- Email: `student_demo_english@example.com`
- Password: `123456`

A Hebrew-language demo account is also available:
`student_demo_hebrew@example.com` / `123456`.

The demo account already has minutes loaded, so no purchase is needed to try a
lesson. [Confirm the balance before submitting.]

Steps:
1. Launch the app and tap **Get started**. The tutorial explains each step;
   tap **Next**, or **Skip** to close it.
2. To log in, open the side menu (top-left button) and tap **Log In**. Then
   sign in with the demo account above. New users can instead create an
   account with email and password, Sign in with Apple, or Google.
3. On the home screen, tap **Photo** to photograph a question, or **Text** to
   type one. Then tap **Find a Teacher**.
4. Choose the subject and how to talk: text, voice, or video. The question is
   sent to available teachers for that subject.
5. When a teacher accepts, the live lesson opens: chat, a shared whiteboard,
   and voice/video. End the lesson from the session controls. Then rate the
   teacher.
6. Side menu → **Minutes**: buy minute packages. **Activity**: past lessons.
   **Settings**: language, notifications, account. **Help & Support**: contact
   us. **Tutorial**: open the tutorial again.
7. **Account deletion:** side menu → Settings → Account & Security → Delete
   Account. Confirm with the account password.
8. **Reporting and blocking a teacher:** during a lesson, tap the flag next to
   the End button. After a lesson, use **Report or block** on the rating
   screen, or open the lesson in **Activity**. The student picks a reason,
   can add details, and can block the teacher in the same step, or block
   without reporting. A blocked teacher is never sent that student's
   questions again, and blocking during a lesson ends it immediately. Blocked
   teachers are listed under Settings → Privacy Controls, where they can be
   unblocked.

**User-generated content (Guideline 1.2):** lesson content (chat, photos,
whiteboard, voice and video) is exchanged only between a student and the
teacher they are connected with; there are no public posts or feeds. Every
report is saved and emailed to our moderation team, which reviews it within
24 hours and acts on it, up to removing the teacher from the platform.
Teachers verify their identity before they can take lessons.

A live lesson needs a teacher online. During review we will keep a demo
teacher online for the subject **[subject]** between **[hours and time zone]**.
If no teacher is available when you test, reply here and we will go online
right away.

**Paid content:** students buy packages of lesson minutes, which pay for
real-time, one-on-one tutoring between the student and a human teacher.
Under Guideline 3.1.3(d) (Person-to-Person Services), this is paid with Apple
Pay, PayPal, or credit card rather than In-App Purchase. No digital content or
features are unlocked by these payments.

**4. External services**

- **Google Firebase:** Authentication (email/password, Sign in with Apple,
  Google sign-in), Cloud Firestore and Realtime Database (profiles, questions,
  teacher availability), Cloud Functions (matching students to teachers,
  billing), Cloud Storage (question photos), Cloud Messaging (notifications),
  Remote Config (in-app text and settings), Analytics and Crashlytics.
- **LiveKit:** real-time voice and video for live lessons.
- **PayPal and Braintree (a PayPal company):** payment processing for Apple
  Pay, PayPal and card payments.
- **Email (SMTP):** account verification and support emails.

The app uses no AI services. All lessons are given by human teachers.

**5. Regional differences**

The app works the same way in all regions where it is available. It is
offered in English and Hebrew, and the user can switch language in Settings.
Prices are in Israeli shekels (₪). Teachers currently teach mainly in
Israel's time zone, so teacher availability can vary by time of day.
[Adjust if the app is limited to particular storefronts.]

**6. Regulated industry / third-party material**

The app does not operate in a highly regulated industry and does not provide
protected third-party material. Teachers are independent tutors who verify
their identity and teaching documents before taking lessons.

Thank you,
[Name]

---

## Screen recording — shot list (physical iPhone, latest iOS)

One continuous take, about 4–6 minutes. Apple asks for it to start with
launching the app.

### Before recording

- Install the new build (tutorial, reporting and blocking) on the iPhone, from
  Xcode or TestFlight. The reviewed build has neither.
- Two devices: the iPhone records the student; a second device runs Pro
  Teacher signed in as the demo teacher, to accept the question.
- Delete Instant Teacher from the iPhone, so the recording opens on a first
  launch with the tutorial.
- Turn on Do Not Disturb. Start recording from Control Center → Screen
  Recording.
- A question goes to every online teacher for its subject, and to all of them
  when fewer than 3 cover it. Record when no real teacher is online (check
  `onlineTeachers`), or have the demo teacher accept at once.

### Steps

1. **Launch** Instant Teacher from the Home Screen and tap **Get started**.
2. **Tutorial:** tap **Next** through all 10 pages. On the last page tick
   **Don't show me again**, then tap **Let's start**.
3. **Registration:** photograph the exercise (or switch to **Text**), tap
   **Find a Teacher**, and create a **new** account with email and password.
   A new account, because step 9 deletes it.
4. **Paid content:** side menu → **Minutes**. Show the packages, tap **Pay**,
   and cancel at the Apple Pay sheet. If the new account has no minutes,
   verifying its email grants the free minutes the lesson needs.
5. **Live lesson:** ask the question; the demo teacher accepts on the second
   device. Show a few chat messages, the **Board** with a quick sketch, and
   switch to voice or video. End the lesson.
6. **Rating:** give stars and a short comment, and send.
7. **Report and block:** side menu → **Activity** → the lesson →
   **Report or block**. Pick a reason, keep **Also block** ticked, send, and
   show the thank-you screen.
8. **Unblock:** **Settings → Privacy Controls**. Show the teacher under
   **Blocked teachers**, then tap **Unblock**.
9. **Account deletion:** **Settings → Account & Security → Delete Account**.
   Enter the password and confirm; the app returns to the start screen.
10. **Login:** side menu → **Log In**, sign in with
    `student_demo_english@example.com`. Stop on the home screen.

Attach the video to the reply in App Store Connect, and fill in `[version]`
(the iPhone's iOS version) in section 1.

## Before resubmitting

- Submit Instant Teacher 1.0.6 (build 7), the build the reply names, and
  select it on the version page before submitting.
- The backend for reporting and blocking is deployed (2026-10-10). Make sure
  SMTP is configured in `functions/.env`, so reports reach the support
  recipients by email; without it they are saved but only logged.
- Publish the Remote Config template, so the latest Hebrew text is live:
  `firebase deploy --only remoteconfig` (from `backend/Firebase`).
- The reply promises reviewing reports within 24 hours. Make sure someone
  watches the report emails.
- Make sure the demo student account has a minutes balance.
