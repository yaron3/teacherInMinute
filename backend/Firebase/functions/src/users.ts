import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import * as functionsV1 from "firebase-functions/v1";

const firestore = admin.firestore();

export const onUserCreate = functionsV1.auth.user().onCreate(async (user) => {
  const { uid } = user;
  await firestore.collection("users").doc(uid).set(
    { remainingMinutes: 0, totalMinutes: 0 },
    { merge: true }
  );
  logger.info(`[users] initialized user doc uid=${uid}`);
});
