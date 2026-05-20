"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.scoreTeacher = scoreTeacher;
exports.rankTeachers = rankTeachers;
const firebase_functions_1 = require("firebase-functions");
// FR-B-002: score = 0.6·(ratingAvg/5) + 0.25·acceptRate + 0.15·recencyFactor
// recencyFactor = exp(-hoursAgo / 24)  →  1.0 when just active, decays to ~0 after 72h
function recencyFactor(lastActiveAt) {
    const hoursAgo = (Date.now() - lastActiveAt) / 3600000;
    return Math.exp(-hoursAgo / 24);
}
function scoreTeacher(teacher) {
    return (0.6 * (teacher.ratingAvg / 5) +
        0.25 * teacher.acceptRate +
        0.15 * recencyFactor(teacher.lastActiveAt));
}
// Normalize a subject or topic string for matching:
// strips a leading area prefix ("Math: " → ""), lowercases, removes non-alphanumeric.
// "Math: Algebra" → "algebra", "algebra" → "algebra", "Trigonometry" → "trigonometry"
function normalizeSubject(s) {
    const afterColon = s.includes(": ") ? s.split(": ").slice(1).join(": ") : s;
    return afterColon.toLowerCase().replace(/[^a-z0-9]/g, "");
}
// Returns all eligible (online + matching topic) teachers sorted best-first.
// The dispatcher slices the result per wave, skipping alreadyInvited UIDs.
function rankTeachers(teachers, topic, exclude) {
    var _a;
    const candidates = [];
    const normalizedTopic = normalizeSubject(topic);
    for (const [uid, t] of Object.entries(teachers)) {
        if (exclude.has(uid))
            continue;
        if (t.status !== "online") {
            firebase_functions_1.logger.info(`[scoring] skip uid=${uid} reason=status status=${t.status}`);
            continue;
        }
        // RTDB can deserialize arrays as {0: "algebra", ...} objects when written by mobile SDKs.
        const subjects = Array.isArray(t.subjects) ? t.subjects : Object.values((_a = t.subjects) !== null && _a !== void 0 ? _a : {});
        const matches = subjects.some((s) => normalizeSubject(s) === normalizedTopic);
        if (!matches) {
            firebase_functions_1.logger.info(`[scoring] skip uid=${uid} reason=topic-mismatch subjects=${JSON.stringify(subjects)} topic=${topic}`);
            continue;
        }
        candidates.push({ uid, score: scoreTeacher(t) });
    }
    return candidates.sort((a, b) => b.score - a.score);
}
//# sourceMappingURL=scoring.js.map