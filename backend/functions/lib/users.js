"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onUserCreate = void 0;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
const functionsV1 = require("firebase-functions/v1");
const firestore = admin.firestore();
exports.onUserCreate = functionsV1.auth.user().onCreate(async (user) => {
    const { uid } = user;
    await firestore.collection("users").doc(uid).set({ remainingMinutes: 0, totalMinutes: 0 }, { merge: true });
    firebase_functions_1.logger.info(`[users] initialized user doc uid=${uid}`);
});
//# sourceMappingURL=users.js.map