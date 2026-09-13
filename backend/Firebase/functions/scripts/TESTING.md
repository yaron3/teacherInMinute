# Multi-teacher backend integration test

From `backend/Firebase/functions`, run:

```sh
npm run test:integration:presence
TEACHER_COUNT=20 STUDENT_EMAIL=s2@a.com npm run test:integration:presence
```

Uses real Firebase client authentication and deployed backend functions. Defaults
to `teacher-in-a-moment`, `t1@a.com` through `t3@a.com`, `s1@a.com`, and password
`123456`. `TEACHER_COUNT` supports 2–20; `TEST_PASSWORD` overrides the password.
The student needs at least two existing minutes. No balances are seeded.

Checks sign-in, offline/online student directory visibility, invitation delivery,
offline teacher exclusion, a teacher joining a waiting question, and cancellation
removing the live question and invitations. It restores the teachers' original
status and subjects in `finally`, including after failures. Cancelled question
history remains in Firestore. An interrupted/killed process may need manual cleanup.

Run with dedicated test accounts while their apps are closed. This changes real
presence and creates a real question; other matching online teachers may receive
it. Shared traffic can accept the question or affect ranking, so use a dedicated
test project for deterministic results. This test does not start a billed lesson.

To target another deployment set `FIREBASE_PROJECT_ID`, `FIREBASE_API_KEY`,
`FIREBASE_DATABASE_URL`, and `FIREBASE_FUNCTIONS_URL`. All must refer to that
deployment. Network calls time out after 20 seconds and polling after 60 seconds.

The regular offline regression suite remains `npm test -- --runInBand`.

## Full two-minute lesson

```sh
npm run test:integration:lesson
```

Uses `s1@a.com` and `t1@a.com`–`t3@a.com`. All three must receive a valid
invitation before they race to accept. Exactly one must succeed; both others
must return `ALREADY_EXISTS`. Both participants join the same lesson, then
exchange six real RTDB chat messages, with every message read back by the other
participant. After two minutes the student ends the lesson.

The test checks a two-minute debit, earnings against the lesson's stamped rate
and teacher share, unchanged losing-teacher earnings, completed question and
lesson records, persisted chat history, and removal of the live question.
Presence restoration is read back. A timestamped JSON report is written under
`scripts/`; override its destination with `REPORT_PATH`.

This test intentionally consumes existing student minutes and credits real
teacher earnings. It does not seed or restore financial balances. Failed runs
attempt to end an active lesson or cancel a pending question before restoring
presence. Shared traffic and delayed network calls can affect results; use
dedicated idle accounts. Receipt is verified at the backend, not in mobile UI.
