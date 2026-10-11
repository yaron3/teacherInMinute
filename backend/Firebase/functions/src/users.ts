import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import * as functionsV1 from "firebase-functions/v1";

const firestore = admin.firestore();

export const onUserCreate = functionsV1.auth.user().onCreate(async (user) => {
  const { uid } = user;
  const userRef = firestore.collection("users").doc(uid);
  // Only fills what is missing: a slow start of this trigger must not wipe
  // minutes already credited, such as the sign-up reward (./signupRewards).
  await firestore.runTransaction(async (tx) => {
    const data = (await tx.get(userRef)).data();
    const missing: Record<string, number> = {};
    if (data?.remainingMinutes === undefined) missing.remainingMinutes = 0;
    if (data?.totalMinutes === undefined) missing.totalMinutes = 0;
    if (Object.keys(missing).length) tx.set(userRef, missing, { merge: true });
  });
  logger.info(`[users] initialized user doc uid=${uid}`);
});
