#!/usr/bin/env node
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { randomUUID } = require('node:crypto');
const { setTimeout: sleep } = require('node:timers/promises');
const { login, rtdb, call, request, eventually, project, KEEP_ALIVE } = require('./test-teacher-presence');

const reportPath = path.resolve(process.env.REPORT_PATH || `scripts/lesson-result-${Date.now()}.json`);
const report = { project, startedAt: new Date().toISOString(), checks: [], messages: [], cleanup: [] };
function save() { fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n'); }
function pass(label, details) {
  report.checks.push({ label, result: 'PASS', details, at: new Date().toISOString() });
  console.log(`PASS ${label}${details ? ': ' + JSON.stringify(details) : ''}`);
  save();
}
function decode(v) {
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('stringValue' in v) return v.stringValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(decode);
  if ('mapValue' in v) return Object.fromEntries(Object.entries(v.mapValue.fields || {}).map(([k, x]) => [k, decode(x)]));
  return null;
}
async function document(account, docPath) {
  const body = await request(`https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/${docPath}`, {
    headers: { Authorization: `Bearer ${account.token}` },
  });
  return Object.fromEntries(Object.entries(body.fields || {}).map(([k, v]) => [k, decode(v)]));
}
const money = n => Math.round(n * 100) / 100;
const balances = user => ({ remainingMinutes: user.remainingMinutes, earnings: user.earnings ?? 0, totalEarnings: user.totalEarnings ?? 0 });

async function main() {
  save();
  const [student, ...teachers] = await Promise.all([
    login(process.env.STUDENT_EMAIL || 's1@a.com'), ...[1, 2, 3].map(i => login(`t${i}@a.com`)),
  ]);
  pass('Four accounts authenticated', [student, ...teachers].map(a => a.email));
  const before = await Promise.all([student, ...teachers].map(a => document(a, `users/${a.uid}`)));
  report.before = Object.fromEntries([student, ...teachers].map((a, i) => [a.email, balances(before[i])]));
  assert(Number.isFinite(before[0].remainingMinutes) && before[0].remainingMinutes >= 2, 'Student needs at least two existing minutes');
  pass('Original balances captured', report.before);
  const originals = await Promise.all(teachers.map(t => rtdb(t, `teachers/${t.uid}`)));
  const changed = [];
  let qid;
  let ended = false;
  let failure;
  try {
    for (let i = 0; i < teachers.length; i++) {
      changed.push(i);
      await rtdb(teachers[i], `teachers/${teachers[i].uid}`, { status: 'online', subjects: ['algebra'], ...KEEP_ALIVE });
    }
    await eventually('All three teachers appear online', async () => {
      const directory = await rtdb(student, 'onlineTeachers') || {};
      return teachers.every(t => directory[t.uid]?.subjects?.includes('algebra'));
    });
    pass('Three teachers online with algebra');
    ({ questionId: qid } = await call(student, 'createQuestion', {
      topic: 'algebra', conversationType: 'text',
      text: `[Live two-minute backend test] Please explain how to solve 2x + 5 = 15. ${Date.now()}`,
    }));
    assert(qid);
    report.questionId = qid;
    pass('Student question created', { questionId: qid });
    const invites = await eventually('All three teachers receive the question', async () => {
      const values = await Promise.all(teachers.map(t => rtdb(t, `teacherInvites/${t.uid}/${qid}`)));
      return values.every(v => v?.topic === 'algebra' && v.conversationType === 'text' && v.expiresAt > Date.now()) && values;
    });
    pass('All three invitations verified', teachers.map((t, i) => ({ email: t.email, wave: invites[i].wave })));

    const attempts = await Promise.allSettled(teachers.map(t => call(t, 'acceptInvite', { questionId: qid })));
    report.acceptance = attempts.map((a, i) => ({ email: teachers[i].email, result: a.status,
      ...(a.status === 'rejected' ? { code: a.reason.code, error: a.reason.message } : {}) }));
    save();
    assert.equal(attempts.filter(a => a.status === 'fulfilled').length, 1, 'Exactly one teacher must win');
    for (const attempt of attempts.filter(a => a.status === 'rejected')) {
      assert.equal(attempt.reason.code, 'ALREADY_EXISTS', 'Losing teachers must be rejected because question was claimed');
    }
    const winnerIndex = attempts.findIndex(a => a.status === 'fulfilled');
    const winner = teachers[winnerIndex];
    report.winner = winner.email;
    pass('One winner and two losing acceptance attempts', report.acceptance);
    const accepted = await document(student, `questions/${qid}`);
    assert.equal(accepted.acceptedByTeacher, winner.uid);
    assert.equal((await call(student, 'getQuestionStatus', { questionId: qid })).status, 'accepted');
    await eventually('All three invitation signals cleared after acceptance', async () =>
      (await Promise.all(teachers.map(t => rtdb(t, `teacherInvites/${t.uid}/${qid}`)))).every(v => v === null));
    pass('Student sees accepted winner and invitation signals cleared');

    const started = await call(student, 'startLesson', { questionId: qid });
    report.lessonId = started.lessonId;
    const deadline = Date.now() + 120_000;
    const teacherStarted = await call(winner, 'startLesson', { questionId: qid });
    assert.equal(teacherStarted.lessonId, started.lessonId);
    const active = await document(student, `questions/${qid}`);
    assert.equal(active.status, 'in_progress');
    assert(active.joinedParticipants.includes(student.uid) && active.joinedParticipants.includes(winner.uid));
    report.pricing = { currency: active.currencyCode, pricePerMinute: active.pricePerMinute, teacherShare: active.teacherShare };
    pass('Both participants joined the same lesson', { lessonId: started.lessonId, ...report.pricing });

    const texts = ['How do I isolate x?', 'Subtract 5 from both sides: 2x = 10.', 'Then divide both sides by 2?', 'Yes. That gives x = 5.', 'Checking: 2 times 5 plus 5 equals 15.', 'Correct. Your solution is x = 5.'];
    const chatStart = Date.now();
    for (let i = 0; i < texts.length; i++) {
      await sleep(Math.max(0, chatStart + i * 18_000 - Date.now()));
      const sender = i % 2 === 0 ? student : winner;
      const receiver = i % 2 === 0 ? winner : student;
      const id = randomUUID();
      const message = { text: texts[i], senderUid: sender.uid, senderRole: i % 2 === 0 ? 'student' : 'teacher', createdAt: Date.now(), kind: 'text' };
      await rtdb(sender, `questions/${qid}/messages/${id}`, message);
      assert.deepEqual(await rtdb(receiver, `questions/${qid}/messages/${id}`), message);
      report.messages.push({ id, sender: sender.email, text: texts[i], deliveredAt: new Date().toISOString() });
      pass(`Chat message ${i + 1} read by other participant`);
    }
    await sleep(Math.max(0, deadline - Date.now()));
    pass('Two-minute session elapsed');
    await call(student, 'endLesson', { questionId: qid });
    ended = true;

    const completed = await document(student, `questions/${qid}`);
    const lesson = await document(student, `lessons/${started.lessonId}`);
    const after = await Promise.all([student, ...teachers].map(a => document(a, `users/${a.uid}`)));
    report.after = Object.fromEntries([student, ...teachers].map((a, i) => [a.email, balances(after[i])]));
    report.settlement = { status: completed.status, durationSeconds: completed.durationSeconds,
      startedAt: completed.startedAt, acceptedAt: completed.acceptedAt, endedAt: completed.endedAt,
      cost: completed.cost, teacherEarnings: completed.teacherEarnings, currency: completed.currencyCode,
      minutesDeducted: money(before[0].remainingMinutes - after[0].remainingMinutes),
      winnerEarningsIncrease: money((after[winnerIndex + 1].earnings ?? 0) - (before[winnerIndex + 1].earnings ?? 0)) };
    save();
    assert.equal(completed.status, 'completed');
    assert.equal(lesson.status, 'completed');
    assert.equal(completed.durationSeconds, 120, 'Two minutes must be billed');
    assert.equal(report.settlement.minutesDeducted, 2);
    const expectedCost = money(2 * active.pricePerMinute);
    const expectedEarnings = money(expectedCost * active.teacherShare);
    assert.equal(completed.cost, expectedCost);
    assert.equal(completed.teacherEarnings, expectedEarnings);
    assert.equal(report.settlement.winnerEarningsIncrease, expectedEarnings);
    assert.equal(money((after[winnerIndex + 1].totalEarnings ?? 0) - (before[winnerIndex + 1].totalEarnings ?? 0)), expectedEarnings);
    for (let i = 0; i < teachers.length; i++) if (i !== winnerIndex) {
      assert.equal(after[i + 1].earnings ?? 0, before[i + 1].earnings ?? 0);
      assert.equal(after[i + 1].totalEarnings ?? 0, before[i + 1].totalEarnings ?? 0);
    }
    pass('Student debit, winner earnings, and unchanged loser earnings match pricing', report.settlement);
    for (const message of report.messages) assert.equal(completed.messages[message.id].text, message.text);
    assert.equal(await rtdb(student, `questions/${qid}`), null);
    pass('Completed lesson retains all six chat messages and live question is removed');
  } catch (error) {
    failure = error;
    report.error = error.message;
  } finally {
    if (qid && !ended) {
      try {
        const state = await document(student, `questions/${qid}`);
        if (state.status === 'in_progress') await call(student, 'endLesson', { questionId: qid });
        else if (['searching', 'accepted', 'unanswered'].includes(state.status)) await call(student, 'cancelQuestion', { questionId: qid });
        report.cleanup.push('Question ended/cancelled or already terminal');
      } catch (error) { report.cleanup.push(`FAILED question cleanup: ${error.message}`); failure ||= error; }
    }
    for (const i of changed) {
      try {
        const original = originals[i] || {};
        await rtdb(teachers[i], `teachers/${teachers[i].uid}`, { status: original.status ?? null, subjects: original.subjects ?? null });
        const restored = await rtdb(teachers[i], `teachers/${teachers[i].uid}`) || {};
        assert.equal(restored.status ?? null, original.status ?? null);
        assert.deepEqual(restored.subjects ?? null, original.subjects ?? null);
        report.cleanup.push(`${teachers[i].email}: original status and subjects restored and read back`);
      } catch (error) { report.cleanup.push(`FAILED ${teachers[i].email}: ${error.message}`); failure ||= error; }
    }
    report.finishedAt = new Date().toISOString();
    report.result = failure ? 'FAIL' : 'PASS';
    save();
    console.log(JSON.stringify({ result: report.result, cleanup: report.cleanup, reportPath }));
  }
  if (failure) throw failure;
}
main().catch(error => {
  report.result = 'FAIL'; report.error = error.message; save();
  console.error(`FAIL ${error.message}; report: ${reportPath}`);
  process.exitCode = 1;
});
