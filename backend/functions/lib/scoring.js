"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.scoreTeacher = scoreTeacher;
exports.rankTeachers = rankTeachers;
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
// Returns all eligible (online + matching topic) teachers sorted best-first.
// The dispatcher slices the result per wave, skipping alreadyInvited UIDs.
function rankTeachers(teachers, topic, exclude) {
    const candidates = [];
    for (const [uid, t] of Object.entries(teachers)) {
        if (exclude.has(uid))
            continue;
        if (t.status !== "online")
            continue;
        if (!Array.isArray(t.subjects) || !t.subjects.includes(topic))
            continue;
        candidates.push({ uid, score: scoreTeacher(t) });
    }
    return candidates.sort((a, b) => b.score - a.score);
}
//# sourceMappingURL=scoring.js.map