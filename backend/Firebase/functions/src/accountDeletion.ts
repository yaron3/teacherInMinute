import * as admin from "firebase-admin";
import { CallableRequest, HttpsError, onCall } from "firebase-functions/v2/https";

/** Never accept a target UID or a password from the caller. Firebase Auth verifies it. */
export function assertDeletionRequest(req: Pick<CallableRequest, "auth" | "data">, now = Date.now()): string {
  if (!req.auth) throw new HttpsError("unauthenticated", "Sign in before deleting your account.");
  if (req.data?.confirmDeletion !== true) {
    throw new HttpsError("invalid-argument", "Confirm permanent deletion of your data and balance.");
  }
  const authenticatedAt = Number(req.auth.token.auth_time) * 1000;
  if (!Number.isFinite(authenticatedAt) || authenticatedAt > now || now - authenticatedAt > 5 * 60 * 1000 ||
      req.auth.token.firebase?.sign_in_provider !== "password") {
    throw new HttpsError("failed-precondition", "Cancel and verify your email and password again before deleting your account.");
  }
  return req.auth.uid;
}

async function removeMatches(query: FirebaseFirestore.Query): Promise<void> {
  const firestore = admin.firestore();
  // Repeat from the beginning after deletion so accounts with >500 records are fully removed.
  for (;;) {
    const page = await query.limit(100).get();
    if (page.empty) return;
    for (const doc of page.docs) await firestore.recursiveDelete(doc.ref);
  }
}

export async function deleteAccountData(uid: string): Promise<void> {
  const firestore = admin.firestore();
  const database = admin.database();
  const bucket = admin.storage().bucket();
  const questions = new Map<string, FirebaseFirestore.QueryDocumentSnapshot>();
  for (const field of ["studentUid", "acceptedByTeacher", "demoTeacherUid"]) {
    const snapshot = await firestore.collection("questions").where(field, "==", uid).get();
    snapshot.docs.forEach(doc => questions.set(doc.id, doc));
  }
  // Do not remove a lesson or its billing records while it is running.
  if ([...questions.values()].some(doc => ["searching", "accepted", "in_progress"].includes(doc.data().status))) {
    throw new HttpsError("failed-precondition", "End your active lesson or cancel your search before deleting your account.");
  }
  for (const field of ["studentUid", "teacherUid"]) {
    const lessons = await firestore.collection("lessons").where(field, "==", uid).get();
    if (lessons.docs.some(doc => doc.data().status === "in_progress")) {
      throw new HttpsError("failed-precondition", "End your active lesson before deleting your account.");
    }
  }

  for (const question of questions.values()) {
    const invites = await question.ref.collection("invites").listDocuments();
    for (const invite of invites) await database.ref(`teacherInvites/${invite.id}/${question.id}`).remove();
    await database.ref(`questions/${question.id}`).remove();
    await database.ref(`lessonPresence/${question.id}`).remove();
    await bucket.deleteFiles({ prefix: `boardSnapshots/${question.id}/` });
    await firestore.recursiveDelete(question.ref);
  }
  for (const [collection, field] of [
    ["lessons", "studentUid"], ["lessons", "teacherUid"],
    ["paymentCheckouts", "uid"], ["billingSessions", "uid"],
    ["contactRequests", "userId"], ["coupons", "studentUserId"],
  ]) {
    await removeMatches(firestore.collection(collection).where(field, "==", uid));
  }

  // Legacy chat threads use participant UIDs in their document ID, including
  // parent documents that have only subcollections and no fields of their own.
  for (const thread of await firestore.collection("messages").listDocuments()) {
    if (thread.id.startsWith(`${uid}_`) || thread.id.endsWith(`_${uid}`)) {
      await firestore.recursiveDelete(thread);
    }
  }
  // Remove invitations and ratings on records belonging to other users too.
  // Invitations use the teacher UID as their document ID.
  const invitedQuestions = await firestore.collection("questions").where("alreadyInvited", "array-contains", uid).get();
  for (const question of invitedQuestions.docs) {
    await firestore.recursiveDelete(question.ref.collection("invites").doc(uid));
    await question.ref.update({ alreadyInvited: admin.firestore.FieldValue.arrayRemove(uid) });
  }
  for (const teacher of await firestore.collection("teachers").listDocuments()) {
    await removeMatches(teacher.collection("ratings").where("studentId", "==", uid));
  }
  for (const role of ["student", "teacher"]) {
    const claims = await firestore.collection("emailRewardClaims").where(`${role}.uid`, "==", uid).get();
    for (const claim of claims.docs) {
      await firestore.runTransaction(async tx => {
        const current = (await tx.get(claim.ref)).data();
        if (current?.[role]?.uid !== uid) return;
        if (Object.keys(current).every(key => key === role)) tx.delete(claim.ref);
        else tx.update(claim.ref, { [role]: admin.firestore.FieldValue.delete() });
      });
    }
  }
  const demoRequests = await database.ref("demoStudent/requests").once("value");
  const demoDeletes: Record<string, null> = {};
  demoRequests.forEach(child => {
    if (child.val()?.teacherUid === uid) demoDeletes[child.key!] = null;
  });
  if (Object.keys(demoDeletes).length) await database.ref("demoStudent/requests").update(demoDeletes);

  for (const prefix of ["profileImages", "documents", "questionImages"]) {
    await bucket.deleteFiles({ prefix: `${prefix}/${uid}/` });
  }
  for (const path of ["teachers", "onlineTeachers", "teacherInvites", "users"]) {
    await database.ref(`${path}/${uid}`).remove();
  }
  // Recursive deletion includes every purchase, payout setting, balance, inbox,
  // profile and any nested subcollections. Auth is deleted only after this succeeds.
  for (const collection of ["teachers", "rateLimits", "users"]) {
    await firestore.recursiveDelete(firestore.collection(collection).doc(uid));
  }
}

export const deleteAccount = onCall({ timeoutSeconds: 540 }, async req => {
  const uid = assertDeletionRequest(req);
  // Reject revoked/disabled sessions as well as expired tokens.
  const bearer = req.rawRequest.headers.authorization?.match(/^Bearer (.+)$/i)?.[1];
  if (!bearer) throw new HttpsError("unauthenticated", "Sign in again.");
  const token = await admin.auth().verifyIdToken(bearer, true);
  if (token.uid !== uid) throw new HttpsError("unauthenticated", "Sign in again.");
  await deleteAccountData(uid);
  await admin.auth().deleteUser(uid);
  return { deleted: true };
});
