"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.findTeachers = void 0;
const https_1 = require("firebase-functions/v2/https");
const firebase_functions_1 = require("firebase-functions");
const admin = require("firebase-admin");
const uuid_1 = require("uuid");
admin.initializeApp();
const db = admin.database();
/**
 * Inserts a candidate into the top-3 list if it qualifies.
 * Mutates and returns the sorted (desc) array.
 */
function tryInsert(top, candidate) {
    if (top.length < 3) {
        top.push(candidate);
        top.sort((a, b) => b.grade - a.grade);
        return;
    }
    // Find the weakest slot
    let lowestIdx = 0;
    for (let i = 1; i < top.length; i++) {
        if (top[i].grade < top[lowestIdx].grade)
            lowestIdx = i;
    }
    if (candidate.grade > top[lowestIdx].grade) {
        top[lowestIdx] = candidate;
        top.sort((a, b) => b.grade - a.grade);
    }
}
function allMaxRated(top) {
    return top.length === 3 && top.every((t) => t.grade >= 5);
}
/**
 * POST /findTeachers
 *
 * Body / query params:
 *   field       {string}  – teacher specialisation field
 *   subfield    {string}  – subfield under field
 *   question    {string}  – the student's question (stored on the request)
 *   request_id? {string}  – if provided, appends to an existing active request
 *
 * Expected DB shape:
 *   teachers/<id>/status          "online" | "offline"
 *   teachers/<id>/grade           number  (0–5)
 *   teachers/<id>/<field>/<subfield>  any truthy value → teacher covers this topic
 *
 * Writes:
 *   active_requests/<request_id>/field
 *   active_requests/<request_id>/subfield
 *   active_requests/<request_id>/question
 *   active_requests/<request_id>/timestamp
 *   active_requests/<request_id>/bided/<teacher_id>/grade
 *   active_requests/<request_id>/bided/<teacher_id>/assignedAt
 *
 * Returns: { request_id }
 */
exports.findTeachers = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b, _c;
    const params = Object.assign(Object.assign({}, req.query), req.body);
    const { field, subfield, question, request_id } = params;
    if (!field || !subfield || !question) {
        res.status(400).json({ error: "Missing required parameters: field, subfield, question" });
        return;
    }
    try {
        const teachersSnap = await db.ref("teachers").once("value");
        if (!teachersSnap.exists()) {
            res.status(404).json({ error: "No teachers found" });
            return;
        }
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const teachers = teachersSnap.val();
        let top = [];
        // ── Mode: append to existing request ────────────────────────────────────
        if (request_id) {
            const bidedSnap = await db.ref(`active_requests/${request_id}/bided`).once("value");
            if (bidedSnap.exists()) {
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                const bided = bidedSnap.val();
                const removeOps = [];
                for (const [tid, data] of Object.entries(bided)) {
                    const t = teachers[tid];
                    if (!t || t.status !== "online") {
                        // Teacher went offline – evict from the active request
                        removeOps.push(db.ref(`active_requests/${request_id}/bided/${tid}`).remove());
                    }
                    else {
                        top.push({ id: tid, grade: (_b = (_a = data.grade) !== null && _a !== void 0 ? _a : t.grade) !== null && _b !== void 0 ? _b : 0 });
                    }
                }
                await Promise.all(removeOps);
                top.sort((a, b) => b.grade - a.grade);
            }
        }
        // ── Select top-3 from matching online teachers ───────────────────────────
        if (!allMaxRated(top)) {
            const alreadySelected = new Set(top.map((t) => t.id));
            for (const [tid, teacher] of Object.entries(teachers)) {
                if (alreadySelected.has(tid))
                    continue;
                if (teacher.status !== "online")
                    continue;
                // Match field + subfield
                const fieldData = teacher[field];
                if (!fieldData || !fieldData[subfield])
                    continue;
                tryInsert(top, { id: tid, grade: (_c = teacher.grade) !== null && _c !== void 0 ? _c : 0 });
                if (allMaxRated(top))
                    break; // early exit – can't do better than 5★ × 3
            }
        }
        if (top.length === 0) {
            res.status(404).json({ error: "No matching online teachers found" });
            return;
        }
        // ── Persist to Realtime DB ───────────────────────────────────────────────
        const finalRequestId = request_id !== null && request_id !== void 0 ? request_id : (0, uuid_1.v4)();
        const requestRef = db.ref(`active_requests/${finalRequestId}`);
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const updates = {
            field,
            subfield,
            question,
            updatedAt: admin.database.ServerValue.TIMESTAMP,
        };
        // Only set createdAt on first write
        if (!request_id) {
            updates.createdAt = admin.database.ServerValue.TIMESTAMP;
        }
        for (const entry of top) {
            updates[`bided/${entry.id}`] = {
                grade: entry.grade,
                assignedAt: admin.database.ServerValue.TIMESTAMP,
            };
        }
        await requestRef.update(updates);
        res.status(200).json({ request_id: finalRequestId });
    }
    catch (err) {
        firebase_functions_1.logger.error("findTeachers error", err);
        res.status(500).json({ error: "Internal server error" });
    }
});
//# sourceMappingURL=index.js.map