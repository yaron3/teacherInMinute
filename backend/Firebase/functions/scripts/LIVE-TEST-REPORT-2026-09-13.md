# Live backend integration report — 2026-09-13

Target: `teacher-in-a-moment`, live Firebase Authentication, Realtime Database,
and deployed HTTPS callable functions. Requests used ordinary client credentials,
not the Admin SDK or mocks. User explicitly approved the live run.

## Outcome

The 20-teacher run was blocked by nine invalid teacher logins. A subsequent run
with `t1@a.com` through `t10@a.com` and `s1@a.com` completed successfully (exit 0).
All presence, invitation, late-arrival, and cancellation assertions passed.

## Authentication audit

All accounts were tested with the supplied password, which is omitted here.

| Accounts | Actual result |
| --- | --- |
| `s1@a.com` | Sign-in passed |
| `t1@a.com`–`t10@a.com` | All ten sign-ins passed |
| `t12@a.com` | Sign-in passed; not included in the subsequent scenario run |
| `t11@a.com`, `t13@a.com`–`t20@a.com` | All nine returned HTTP 400 `INVALID_LOGIN_CREDENTIALS` |

Firebase's response does not establish whether these accounts are absent or their
password differs. The initial attempt stopped at the first rejection (`t13`).
The script was then improved to await and report every sign-in. The complete
audit confirmed 12 successes and 9 failures among 21 accounts. Both authentication
attempts stopped before presence or question mutations.

## Live scenario results

Command, run from `backend/Firebase/functions`:

```sh
TEACHER_COUNT=10 node scripts/test-teacher-presence.js
```

Question created: `49bc5347-3fd1-40c5-bee6-07acf0ff1ff5`.
Student: `s1@a.com`. Topic: `algebra`. Conversation type: `text`.
Question text asked to solve `2x + 5 = 15`, marked as a backend integration test.

| Test | Action and assertion | Actual result |
| --- | --- | --- |
| Participant login | Authenticate the student and all ten teachers | PASS, 11/11 |
| Offline visibility | Set all ten teachers offline; read `onlineTeachers` as the student | PASS, all ten absent |
| Online visibility | Set `t1`–`t9` online with algebra; poll the student's directory | PASS, all nine appeared with algebra |
| Question creation | Call `createQuestion` as `s1` | PASS, returned the question ID above |
| Invitation delivery | Read question invitations as `t1`–`t9` | PASS, at least one contained algebra and text conversation type |
| Offline exclusion | Read `t10`'s invitation before bringing that teacher online | PASS, invitation was absent |
| Late arrival | Bring `t10` online after question creation; poll its invitation | PASS, algebra invitation arrived |
| Cancellation state | Call `cancelQuestion`, then `getQuestionStatus` | PASS, status was `cancelled` |
| Cancellation cleanup | Read the live question and all ten teachers' invitations | PASS, all eleven paths were absent |
| Presence restoration | Restore original status and subjects for all ten teachers in `finally` | All restoration writes succeeded; no cleanup errors |

## Effects and verification limits

- One question was created and cancelled during the successful scenario run.
  Its cancelled history remains in Firestore.
- Teachers' original status and subjects were snapshotted before mutation and
  restored through successful writes. Restoration was not independently read
  back, and the public directory was not polled again after restoration.
- No lesson was accepted or started, and the test did not seed balances or
  invoke billing. Audio/video, lesson completion, charges, earnings, and
  concurrent teacher acceptance were not tested.
- Invitation delivery asserted at least one eligible initial teacher received
  the question, not that all nine received it. The test did not record which
  initial teacher received it, precise latency, or dispatch wave sizes/order.
- Late-arrival success proves eventual delivery after going online; this test
  does not distinguish status-trigger backfill from a scheduled dispatch wave.
- Offline exclusion was a point-in-time check before `t10` went online.
- This was a shared live deployment. Matching teachers outside the test group
  could receive the question; the test did not inventory those invitations.
- Students other than `s1` were not tested. `t12` was authenticated only. The
  nine rejected teachers could not participate, so this is not a successful
  20-teacher scenario or a load/performance test.

The previous offline regression run passed 190 tests across 13 suites. Those
results are separate from the live results above.
