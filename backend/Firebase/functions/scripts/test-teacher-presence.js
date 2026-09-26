#!/usr/bin/env node
'use strict';

// Real client requests: no Admin SDK, balance seeding, or fabricated ratings.
const assert = require('node:assert/strict');
const { setTimeout: sleep } = require('node:timers/promises');

const project = process.env.FIREBASE_PROJECT_ID || 'teacher-in-a-moment';
const apiKey = process.env.FIREBASE_API_KEY || 'AIzaSyAx11X0ezhughh9_Dep5oTeEnj5U5KaXQY';
const database = process.env.FIREBASE_DATABASE_URL || `https://${project}-default-rtdb.firebaseio.com`;
const functions = process.env.FIREBASE_FUNCTIONS_URL || `https://us-central1-${project}.cloudfunctions.net`;
const password = process.env.TEST_PASSWORD || '123456';
const count = Number(process.env.TEACHER_COUNT || 3);
const studentEmail = process.env.STUDENT_EMAIL || 's1@a.com';
const timeout = 60_000;

async function request(url, options = {}) {
  const response = await fetch(url, { ...options, signal: AbortSignal.timeout(20_000) });
  const body = await response.json();
  if (!response.ok || body?.error) {
    // Never include request URLs (RTDB URLs contain authentication tokens).
    const error = new Error(`HTTP ${response.status}: ${body?.error?.message || body?.error || 'Request failed'}`);
    error.code = body?.error?.status;
    throw error;
  }
  return body;
}

async function login(email) {
  try {
    const body = await request(`https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${apiKey}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    });
    return { email, uid: body.localId, token: body.idToken };
  } catch (error) {
    throw new Error(`Login ${email}: ${error.message}`);
  }
}

// What a running app sends with `status: 'online'`: a keep-alive on the
// server's clock (see functions/src/keepAlive.ts). Without it, a test account
// that has ever used the app reads as silent, and dispatch skips it.
const KEEP_ALIVE = { lastSeenAt: { '.sv': 'timestamp' } };

function rtdb(account, path, patch) {
  return request(`${database}/${path}.json?auth=${account.token}`, patch === undefined ? {} : {
    method: 'PATCH', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(patch),
  });
}

async function call(account, name, data) {
  const body = await request(`${functions}/${name}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${account.token}` },
    body: JSON.stringify({ data }),
  });
  return body.result;
}

async function eventually(label, check) {
  const deadline = Date.now() + timeout;
  do {
    const result = await check();
    if (result) {
      console.log(`PASS ${label}`);
      return result;
    }
    await sleep(1000);
  } while (Date.now() < deadline);
  throw new Error(`Timed out: ${label}`);
}

async function main() {
  assert(Number.isInteger(count) && count >= 2 && count <= 20, 'TEACHER_COUNT must be an integer from 2 to 20');
  console.log(`Target: ${project}; teachers t1@a.com–t${count}@a.com; student ${studentEmail}`);
  const emails = [studentEmail, ...Array.from({ length: count }, (_, i) => `t${i + 1}@a.com`)];
  const logins = await Promise.allSettled(emails.map(login));
  for (const [i, result] of logins.entries()) {
    console.log(result.status === 'fulfilled'
      ? `PASS login ${emails[i]}` : `FAIL ${result.reason.message}`);
  }
  const rejected = logins.filter(result => result.status === 'rejected');
  assert.equal(rejected.length, 0, `${rejected.length}/${emails.length} accounts failed login; no presence or question changes made`);
  const accounts = logins.map(result => result.value);
  const [student, ...teachers] = accounts;
  console.log(`PASS signed in ${accounts.length} test accounts`);

  // Snapshot every participant before making any changes. Restore only the
  // client-owned fields we change; backend-owned ratings remain untouched.
  const originals = await Promise.all(teachers.map(t => rtdb(t, `teachers/${t.uid}`)));
  const changed = [];
  let questionId;
  let failure;
  try {
    for (const [i, teacher] of teachers.entries()) {
      changed.push(i); // Include a write whose response times out in cleanup.
      await rtdb(teacher, `teachers/${teacher.uid}`, { status: 'offline', subjects: ['algebra'] });
    }
    await eventually('offline teachers are absent from student directory', async () => {
      const directory = await rtdb(student, 'onlineTeachers') || {};
      return teachers.every(t => !directory[t.uid]);
    });

    // Keep the final teacher offline to exercise joining a waiting question.
    for (const teacher of teachers.slice(0, -1)) {
      await rtdb(teacher, `teachers/${teacher.uid}`, { status: 'online', ...KEEP_ALIVE });
    }
    await eventually('online teachers appear with algebra in student directory', async () => {
      const directory = await rtdb(student, 'onlineTeachers') || {};
      return teachers.slice(0, -1).every(t => directory[t.uid]?.subjects?.includes('algebra'));
    });

    ({ questionId } = await call(student, 'createQuestion', {
      topic: 'algebra', conversationType: 'text',
      text: `[Backend integration test] Please solve 2x + 5 = 15. ${Date.now()}`,
    }));
    assert(questionId, 'createQuestion must return questionId');
    console.log(`Created question ${questionId}`);
    await eventually('an online test teacher receives the student question', async () => {
      const invites = await Promise.all(teachers.slice(0, -1).map(t => rtdb(t, `teacherInvites/${t.uid}/${questionId}`)));
      return invites.some(invite => invite?.topic === 'algebra' && invite?.conversationType === 'text');
    });

    const lateTeacher = teachers.at(-1);
    assert.equal(await rtdb(lateTeacher, `teacherInvites/${lateTeacher.uid}/${questionId}`), null,
      'offline teacher must not receive an invite');
    console.log('PASS offline teacher is not invited');
    await rtdb(lateTeacher, `teachers/${lateTeacher.uid}`, { status: 'online', ...KEEP_ALIVE });
    await eventually('teacher joining online receives the waiting question', async () => {
      const invite = await rtdb(lateTeacher, `teacherInvites/${lateTeacher.uid}/${questionId}`);
      return invite?.topic === 'algebra';
    });

    await call(student, 'cancelQuestion', { questionId });
    assert.equal((await call(student, 'getQuestionStatus', { questionId })).status, 'cancelled');
    await eventually('cancellation removes live question and test teacher invites', async () => {
      const values = await Promise.all([
        rtdb(student, `questions/${questionId}`),
        ...teachers.map(t => rtdb(t, `teacherInvites/${t.uid}/${questionId}`)),
      ]);
      return values.every(value => value === null);
    });
    questionId = undefined;
  } catch (error) {
    failure = error;
  } finally {
    const cleanupErrors = [];
    if (questionId) {
      try { await call(student, 'cancelQuestion', { questionId }); }
      catch (error) { cleanupErrors.push(`question ${questionId}: ${error.message}`); }
    }
    for (const i of changed) {
      const teacher = teachers[i];
      const original = originals[i] || {};
      try {
        await rtdb(teacher, `teachers/${teacher.uid}`, {
          status: original.status ?? null, subjects: original.subjects ?? null,
        });
      } catch (error) { cleanupErrors.push(`${teacher.email}: ${error.message}`); }
    }
    if (cleanupErrors.length) {
      throw new AggregateError([...(failure ? [failure] : []), ...cleanupErrors.map(e => new Error(e))],
        `Cleanup requires attention: ${cleanupErrors.join('; ')}`);
    }
    console.log('Restored teacher status and subjects');
  }
  if (failure) throw failure;
  console.log('PASS all multi-teacher integration scenarios');
}

module.exports = { login, rtdb, call, request, eventually, project, KEEP_ALIVE };

if (require.main === module) main().catch(error => {
  console.error(`FAIL ${error.message}`);
  process.exitCode = 1;
});
