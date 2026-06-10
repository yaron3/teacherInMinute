#!/usr/bin/env node
/**
 * Integration test — full lesson billing flow (real HTTPS calls, no mocks)
 *
 *  Run:  node integration-test.js
 *        DEBUG=1 node integration-test.js   ← prints full error stacks
 *
 *  Accounts:
 *    Student  s1test@a.com  / 123456
 *    Teacher  t1test@a.com  / 123456
 *
 *  Scenario:
 *    Lesson lasts 1:20 (80 s).  The billing engine floors to the nearest
 *    completed 30-second slot → 60 s → 1.0 minute billed.
 *
 *  Assertions:
 *    8.  Student's remaining minutes decreased by exactly 1.0
 *    9.  Teacher's earnings increased by $0.75  (1 min × $1.00 × 75 %)
 */

'use strict';

// ─── Config ───────────────────────────────────────────────────────────────────

const FIREBASE_API_KEY = 'AIzaSyAx11X0ezhughh9_Dep5oTeEnj5U5KaXQY';
const PROJECT_ID       = 'teacher-in-a-moment';
const RTDB_URL         = 'https://teacher-in-a-moment-default-rtdb.firebaseio.com';
const FUNCTIONS_BASE   = 'https://us-central1-teacher-in-a-moment.cloudfunctions.net';
const FIRESTORE_BASE   =
  `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}/databases/(default)/documents`;

const STUDENT_EMAIL    = 's1test@a.com';
const STUDENT_PASSWORD = '123456';
const TEACHER_EMAIL    = 't1test@a.com';
const TEACHER_PASSWORD = '123456';

const COST_PER_MINUTE  = 1.0;  // written to teacher's Firestore doc before the test
const COMMISSION_RATE  = 0.75; // server default; teacher earns 75 % of lesson cost
const INITIAL_MINUTES  = 20;   // minutes we seed for the student
// Billing runs from startedAt (written by startLesson when both parties connect)
// to endedAt (Timestamp.now() inside endLesson).  The 80 s wait below starts
// immediately after startLesson returns, so the server window is ~81 s:
//   floor(81/30)*30 = 60 s  →  1.0 minute billed.
const LESSON_WAIT_MS   = 80_000; // 1 min 20 sec

// How long to wait for the dispatch function to invite the teacher (cloud
// functions can have a cold-start delay; 3 dispatch waves cover ~36 s total).
const INVITE_POLL_TIMEOUT_MS = 60_000;
const INVITE_POLL_INTERVAL_MS = 2_000;

// ─── Logging ──────────────────────────────────────────────────────────────────

const ts  = () => new Date().toISOString().slice(11, 19);
const log  = (msg) => console.log(`[${ts()}]  ${msg}`);
const pass = (msg) => console.log(`  ✅  ${msg}`);
const fail = (msg) => { console.error(`  ❌  ${msg}`); process.exit(1); };
const sleep = (ms)  => new Promise((r) => setTimeout(r, ms));

// ─── Firebase REST helpers ────────────────────────────────────────────────────

/** Sign in with email/password. Returns { idToken, uid }. */
async function firebaseSignIn(email, password) {
  const url =
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${FIREBASE_API_KEY}`;
  const res  = await fetch(url, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify({ email, password, returnSecureToken: true }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`Login failed for ${email}: ${JSON.stringify(body.error ?? body)}`);
  return { idToken: body.idToken, uid: body.localId };
}

/** Call a Firebase v2 callable function. */
async function callFunction(name, data, idToken) {
  const res = await fetch(`${FUNCTIONS_BASE}/${name}`, {
    method:  'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${idToken}` },
    body:    JSON.stringify({ data }),
  });
  const body = await res.json();
  if (!res.ok || body.error) {
    throw new Error(`${name}() → ${JSON.stringify(body.error ?? body)}`);
  }
  return body.result;
}

/** Overwrite an RTDB path with PUT. */
async function rtdbPut(path, data, idToken) {
  const res = await fetch(`${RTDB_URL}/${path}.json?auth=${idToken}`, {
    method:  'PUT',
    headers: { 'Content-Type': 'application/json' },
    body:    JSON.stringify(data),
  });
  if (!res.ok) throw new Error(`RTDB PUT ${path} → HTTP ${res.status}: ${await res.text()}`);
}

/** Read an RTDB path. Returns null when the node does not exist. */
async function rtdbGet(path, idToken) {
  const res = await fetch(`${RTDB_URL}/${path}.json?auth=${idToken}`);
  if (!res.ok) throw new Error(`RTDB GET ${path} → HTTP ${res.status}: ${await res.text()}`);
  return res.json(); // returns null when absent
}

/** Read a Firestore document as a plain JS object (numeric types unwrapped). */
async function firestoreGet(collection, docId, idToken) {
  const res = await fetch(`${FIRESTORE_BASE}/${collection}/${docId}`, {
    headers: { Authorization: `Bearer ${idToken}` },
  });
  if (!res.ok) throw new Error(`Firestore GET ${collection}/${docId} → HTTP ${res.status}`);
  const body = await res.json();
  const doc = {};
  for (const [k, v] of Object.entries(body.fields ?? {})) {
    if ('doubleValue'  in v) doc[k] = v.doubleValue;
    else if ('integerValue' in v) doc[k] = Number(v.integerValue);
    else if ('stringValue'  in v) doc[k] = v.stringValue;
    else if ('booleanValue' in v) doc[k] = v.booleanValue;
  }
  return doc;
}

/**
 * PATCH specific fields on a Firestore document.
 * Each JS number → doubleValue, string → stringValue.
 */
async function firestorePatch(collection, docId, fields, idToken) {
  const mask = Object.keys(fields)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join('&');
  const fsFields = {};
  for (const [k, v] of Object.entries(fields)) {
    if      (typeof v === 'number')  fsFields[k] = { doubleValue: v };
    else if (typeof v === 'string')  fsFields[k] = { stringValue: v };
    else if (typeof v === 'boolean') fsFields[k] = { booleanValue: v };
  }
  const res = await fetch(`${FIRESTORE_BASE}/${collection}/${docId}?${mask}`, {
    method:  'PATCH',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${idToken}` },
    body:    JSON.stringify({ fields: fsFields }),
  });
  if (!res.ok) {
    throw new Error(`Firestore PATCH ${collection}/${docId} → HTTP ${res.status}: ${await res.text()}`);
  }
}

/**
 * Poll an RTDB path until it returns a non-null value.
 * Throws if timeoutMs elapses without a value.
 */
async function pollRtdb(path, idToken, timeoutMs = INVITE_POLL_TIMEOUT_MS) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const val = await rtdbGet(path, idToken);
    if (val !== null) return val;
    process.stdout.write('.');
    await sleep(INVITE_POLL_INTERVAL_MS);
  }
  process.stdout.write('\n');
  throw new Error(`Timed out after ${timeoutMs / 1000}s waiting for RTDB ${path}`);
}

// ─── Test ─────────────────────────────────────────────────────────────────────

(async () => {
  console.log('\n──── Lesson billing integration test ───────────────────────────────────\n');
  try {

    // ── Step 1 & 2: Login both accounts in parallel ───────────────────────────

    log('Steps 1 & 2  Login student and teacher');
    const [student, teacher] = await Promise.all([
      firebaseSignIn(STUDENT_EMAIL, STUDENT_PASSWORD),
      firebaseSignIn(TEACHER_EMAIL, TEACHER_PASSWORD),
    ]);
    pass(`Student logged in   uid=${student.uid}`);
    pass(`Teacher logged in   uid=${teacher.uid}`);

    // ── Step 3: Teacher goes online + set up for billing ─────────────────────
    //
    // • RTDB teachers/{uid}  — dispatcher reads this to find eligible teachers
    // • Firestore users/{uid}.costPerMinute — endLesson reads this for billing

    log('Step 3  Teacher online + costPerMinute setup');
    await Promise.all([
      rtdbPut(`teachers/${teacher.uid}`, {
        status:       'online',
        subjects:     ['algebra'],
        ratingAvg:    3.0,
        acceptRate:   1.0,
        lastActiveAt: Date.now(),
        displayName:  'Test Teacher T1',
      }, teacher.idToken),
      firestorePatch('users', teacher.uid, { costPerMinute: COST_PER_MINUTE }, teacher.idToken),
    ]);
    pass(`Teacher online in RTDB (subjects: algebra)`);
    pass(`costPerMinute=$${COST_PER_MINUTE} written to Firestore`);

    // ── Baseline snapshots ────────────────────────────────────────────────────

    log(`Seeding student with ${INITIAL_MINUTES} minutes`);
    await firestorePatch('users', student.uid, { remainingMinutes: INITIAL_MINUTES }, student.idToken);
    const studentBefore  = await firestoreGet('users', student.uid, student.idToken);
    const teacherBefore  = await firestoreGet('users', teacher.uid, teacher.idToken);
    const earningsBefore = Number(teacherBefore.earnings ?? teacherBefore.totalEarnings ?? 0);
    pass(`Student starts with ${studentBefore.remainingMinutes} min`);
    log(`Teacher earnings before lesson: $${earningsBefore}`);

    // ── Step 4: Student creates question ──────────────────────────────────────
    //
    // Writing to Firestore triggers dispatchQuestion (Firestore onCreate).
    // The dispatcher fans teachers in waves of 3 → 5 → 10 every 12 s.

    log('Step 4  Student creates algebra question');
    const { questionId } = await callFunction('createQuestion', {
      topic: 'algebra',
      text:  'Please help me solve this algebra problem: 2x + 5 = 15, what is x?',
    }, student.idToken);
    pass(`Question created   qid=${questionId}`);

    // ── Step 5a: Teacher polls RTDB for the invitation ────────────────────────
    //
    // Dispatch writes teacherInvites/{teacherUid}/{questionId} in RTDB.
    // Poll for up to 60 s to cover cold-start + up to 3 dispatch waves (~36 s).

    log(`Step 5  Polling teacherInvites/${teacher.uid}/${questionId} (up to 60 s)`);
    process.stdout.write('  waiting');
    const invite = await pollRtdb(
      `teacherInvites/${teacher.uid}/${questionId}`,
      teacher.idToken,
      INVITE_POLL_TIMEOUT_MS,
    );
    process.stdout.write('\n');
    pass(`Invite arrived   wave=${invite.wave ?? '?'}`);

    // ── Step 5b: Teacher accepts the invitation ───────────────────────────────

    log('Step 5  Teacher accepting invite');
    const accepted = await callFunction('acceptInvite', { questionId }, teacher.idToken);
    pass(`Invite accepted   liveKitRoom=${accepted.liveKitRoom ?? 'n/a'}`);

    // ── Step 5c: Student calls startLesson — billing clock starts here ─────────
    //
    // startLesson writes startedAt = Date.now() to RTDB and Firestore.
    // endLesson now bills from startedAt (fully connected) not acceptedAt,
    // so the 80 s countdown below maps directly to the billed window.

    log('Step 5  Student calling startLesson (billing clock starts here)');
    const { lessonId } = await callFunction('startLesson', { questionId }, student.idToken);
    pass(`Lesson started   lessonId=${lessonId}`);

    // ── Step 6: Wait 1:20 (80 s) ─────────────────────────────────────────────
    //
    // Billing window = startedAt → endedAt.
    // 80 s wait + ~1 s endLesson overhead ≈ 81 s total.
    //   floor(81/30)*30 = 60 s  →  1.0 minute billed

    log(`Step 6  Waiting ${LESSON_WAIT_MS / 1000}s to simulate 1:20 lesson`);
    process.stdout.write('  ');
    const tickInterval = 10_000;
    for (let elapsed = 0; elapsed < LESSON_WAIT_MS; elapsed += tickInterval) {
      await sleep(tickInterval);
      const remaining = Math.ceil((LESSON_WAIT_MS - elapsed - tickInterval) / 1000);
      process.stdout.write(remaining > 0 ? `${remaining}s… ` : '');
    }
    process.stdout.write('\n');
    pass('1:20 elapsed');

    // ── Step 7: Student ends the call ────────────────────────────────────────

    log('Step 7  Student calling endLesson');
    const ended = await callFunction('endLesson', { questionId }, student.idToken);
    pass(`Lesson ended   endedBy=${ended.endedBy}`);

    // Give the Firestore batch a moment to propagate before reading.
    await sleep(2_000);

    // ── Step 8: Validate student remaining minutes ────────────────────────────
    //
    // Expected: 20.0 − 1.0 = 19.0 min

    log('Step 8  Reading student doc');
    const studentAfter    = await firestoreGet('users', student.uid, student.idToken);
    const minutesBefore   = INITIAL_MINUTES;
    const minutesAfter    = studentAfter.remainingMinutes;
    const minutesConsumed = Math.round((minutesBefore - minutesAfter) * 100) / 100;
    log(`  before=${minutesBefore}  after=${minutesAfter}  consumed=${minutesConsumed}`);

    const expectedMinutes = 1.0;
    if (minutesConsumed === expectedMinutes) {
      pass(`Student charged exactly ${expectedMinutes} minute  (${minutesBefore} → ${minutesAfter})`);
    } else {
      fail(
        `Expected ${expectedMinutes} min consumed, got ${minutesConsumed}` +
        `  (before=${minutesBefore}, after=${minutesAfter})`,
      );
    }

    // ── Step 9: Validate teacher earnings ────────────────────────────────────
    //
    // Expected: 1.0 min × $1.00/min × 75% = $0.75
    // Server formula: Math.round(cost * commissionRate * 100) / 100
    //               = Math.round(1.0 * 0.75 * 100) / 100 = $0.75

    log('Step 9  Reading teacher doc');
    const teacherAfter    = await firestoreGet('users', teacher.uid, teacher.idToken);
    const earningsAfter   = Number(teacherAfter.earnings ?? teacherAfter.totalEarnings ?? 0);
    const earningsGained  = Math.round((earningsAfter - earningsBefore) * 100) / 100;
    const expectedEarnings =
      Math.round(expectedMinutes * COST_PER_MINUTE * COMMISSION_RATE * 100) / 100; // $0.75
    log(`  before=$${earningsBefore}  after=$${earningsAfter}  gained=$${earningsGained}  expected=$${expectedEarnings}`);

    if (earningsGained === expectedEarnings) {
      pass(`Teacher earned $${earningsGained}  (expected $${expectedEarnings})`);
    } else {
      fail(
        `Expected teacher earnings +$${expectedEarnings}, got +$${earningsGained}` +
        `  (before=$${earningsBefore}, after=$${earningsAfter})`,
      );
    }

    // ── Cleanup: take teacher offline ─────────────────────────────────────────

    await rtdbPut(`teachers/${teacher.uid}/status`, 'offline', teacher.idToken);
    log('Teacher set back to offline');

    console.log('\n✅  All 2 assertions passed — billing is working correctly.\n');

  } catch (err) {
    console.error(`\n❌  Test failed: ${err.message}`);
    if (process.env.DEBUG) console.error(err.stack);
    process.exit(1);
  }
})();
