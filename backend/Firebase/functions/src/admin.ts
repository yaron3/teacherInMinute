import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { recomputeRegisteredTeacherCount, STATS_COLLECTION, PLATFORM_STATS_DOC } from "./stats";
import { republishAllTeacherPresence, ONLINE_TEACHERS_PATH } from "./presence";

const firestore = admin.firestore();
const db = admin.database();

/**
 * Fallback allowlist, kept so setting the custom claim below cannot lock the
 * operator out of their own console. Remove it — and this constant — once
 * `admin: true` is set on the account and verified to work.
 */
const ADMIN_EMAIL = process.env.ADMIN_EMAIL ?? "yaronj3@gmail.com";

/**
 * Gate for every admin callable.
 *
 * Authorization is the `admin` custom claim, set out-of-band with the Admin
 * SDK (see scripts/set-admin-claim.js). A claim cannot be obtained by
 * registering an address, survives an email change, and is revocable without a
 * redeploy — none of which is true of matching on an email address.
 *
 * `email_verified` is required on both paths. Firebase populates the `email`
 * claim on email/password signup while leaving `email_verified` false, so
 * without this check anyone able to create an account with the allowlisted
 * address would have had full admin.
 */
function assertAdmin(req: CallableRequest): void {
  const token = req.auth?.token;
  const emailVerified = token?.email_verified === true;
  const hasClaim = token?.admin === true;
  const allowlisted = typeof token?.email === "string" && token.email === ADMIN_EMAIL;

  if (!emailVerified || (!hasClaim && !allowlisted)) {
    logger.warn(
      `[admin] access denied uid=${req.auth?.uid ?? "anonymous"} emailVerified=${emailVerified} claim=${hasClaim}`
    );
    throw new HttpsError("permission-denied", "Admin access required");
  }
}

/**
 * Epoch millis for any date the app writes.
 *
 * Dates reach Firestore in three shapes and the console has to render all of
 * them: `Timestamp` from the backend, epoch millis from the RTDB mirror, and
 * ISO-8601 strings from the iOS/Android client (`users/{uid}.createdAt`,
 * `contactRequests.sentAt`). Missing the string case is what left every
 * teacher on the verification queue showing "Joined —".
 */
function tsToMs(value: unknown): number | null {
  if (!value) return null;
  if (typeof value === "number") return value < 1e12 ? value * 1000 : value;
  if (typeof value === "string") {
    const parsed = Date.parse(value);
    if (Number.isFinite(parsed)) return parsed;
    const numeric = Number(value);
    return Number.isFinite(numeric) ? (numeric < 1e12 ? numeric * 1000 : numeric) : null;
  }
  const obj = value as Record<string, unknown>;
  if (typeof obj.toMillis === "function") return (obj as { toMillis: () => number }).toMillis();
  if (typeof obj._seconds === "number") return (obj._seconds as number) * 1000;
  if (typeof obj.seconds === "number") return (obj.seconds as number) * 1000;
  return null;
}

/** `tsToMs` for fields that are only ever dates — a plain number stays a
 *  number, so this must not be used on counters. */
function dateFieldToMs(value: unknown): number | null {
  return tsToMs(value);
}

/**
 * Flattens a document for the console: timestamps become epoch millis at every
 * depth. Nested objects matter now that user documents carry `savedPayPal` and
 * `payoutMethod`, each with a `Timestamp` inside that would otherwise reach the
 * browser as an opaque `{_seconds}` pair.
 */
function serializeDoc(data: Record<string, unknown>): Record<string, unknown> {
  return serializeValue(data) as Record<string, unknown>;
}

function serializeValue(value: unknown, depth = 0): unknown {
  if (value instanceof Timestamp) return value.toMillis();
  if (Array.isArray(value)) {
    return depth > 6 ? value : value.map((v) => serializeValue(v, depth + 1));
  }
  if (value && typeof value === "object") {
    const ms = tsToMs(value);
    if (ms !== null) return ms;
    if (depth > 6) return value;
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = serializeValue(v, depth + 1);
    }
    return out;
  }
  return value;
}

/** The first non-empty string among the alternatives, or null. Profile photos
 *  and names are written under several spellings depending on which client
 *  version created the document. */
function firstString(...values: unknown[]): string | null {
  for (const v of values) {
    if (typeof v === "string" && v.trim().length > 0) return v;
  }
  return null;
}

function numberOrNull(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

/** Lessons and completed questions store money in major units of their own
 *  `currencyCode` (12.5 ILS, not 1250). The console works in cents. */
function majorUnitsToCents(value: unknown): number | null {
  const n = Number(value);
  return Number.isFinite(n) ? Math.round(n * 100) : null;
}

/**
 * The verification / rating record at Firestore `teachers/{uid}`.
 *
 * `rateTeacher` maintains `averageRate` and `ratingCount` here, and
 * `adminVerifyTeacher` writes `verifiedAt`. This replaced the RTDB
 * `ratingAvg` / `acceptRate` fields, which nothing writes any more — the app
 * now only writes `status` and `subjects` to RTDB `teachers/{uid}`.
 */
interface TeacherAggregate {
  verifiedAt: number | null;
  averageRate: number | null;
  ratingCount: number | null;
}

async function readTeacherAggregates(uids: string[]): Promise<Map<string, TeacherAggregate>> {
  const map = new Map<string, TeacherAggregate>();
  if (uids.length === 0) return map;

  const snaps = await firestore.getAll(
    ...uids.map((uid) => firestore.collection("teachers").doc(uid))
  );
  for (const snap of snaps) {
    const data = snap.data() ?? {};
    map.set(snap.id, {
      verifiedAt: dateFieldToMs(data.verifiedAt),
      averageRate: numberOrNull(data.averageRate),
      ratingCount: numberOrNull(data.ratingCount),
    });
  }
  return map;
}

// ─── adminDashboardStatus ─────────────────────────────────────────────────────

/**
 * Recomputes the cached platform counters. Seeds `registeredTeacherCount` for
 * teachers who registered before the counter existed — after that the
 * `onUserRoleChange` trigger keeps it current on its own.
 */
/**
 * Rebuilds the public `onlineTeachers` projection from the authoritative
 * presence node. Run once after deploying the projection — teachers already
 * online will not rewrite `status`, so nothing else would publish them.
 */
export const adminRepublishOnlineTeachers = onCall(async (req) => {
  assertAdmin(req);
  const onlineCount = await republishAllTeacherPresence();
  return { onlineCount };
});

export const adminRecomputePlatformStats = onCall(async (req) => {
  assertAdmin(req);
  const registeredTeacherCount = await recomputeRegisteredTeacherCount();
  return { registeredTeacherCount };
});

export const adminDashboardStatus = onCall(async (req) => {
  assertAdmin(req);

  const [
    presenceSnap,
    onlineSnap,
    rtdbQsSnap,
    searchingCount,
    acceptedCount,
    inProgressCount,
    completedCount,
    unansweredCount,
    cancelledCount,
    userCountSnap,
    activeLessonsSnap,
    teacherUsersSnap,
    platformStatsSnap,
  ] = await Promise.all([
    db.ref("teachers").once("value"),
    db.ref(ONLINE_TEACHERS_PATH).once("value"),
    db.ref("questions").once("value"),
    firestore.collection("questions").where("status", "==", "searching").count().get(),
    firestore.collection("questions").where("status", "==", "accepted").count().get(),
    firestore.collection("questions").where("status", "==", "in_progress").count().get(),
    firestore.collection("questions").where("status", "==", "completed").count().get(),
    firestore.collection("questions").where("status", "==", "unanswered").count().get(),
    firestore.collection("questions").where("status", "==", "cancelled").count().get(),
    firestore.collection("users").count().get(),
    firestore.collection("lessons").where("status", "==", "in_progress").get(),
    firestore.collection("users").where("role", "==", "teacher").get(),
    firestore.collection(STATS_COLLECTION).doc(PLATFORM_STATS_DOC).get(),
  ]);

  // Teachers who uploaded credentials but have no `verifiedAt` on their
  // Firestore `teachers/{uid}` record.
  const teacherUidsWithDocs = teacherUsersSnap.docs
    .filter((d) => ((d.data().uploadedDocuments as string[] | undefined) ?? []).length > 0)
    .map((d) => d.id);

  const teacherAggregates = await readTeacherAggregates(teacherUidsWithDocs);
  const pendingVerificationCount = teacherUidsWithDocs.filter(
    (uid) => !teacherAggregates.get(uid)?.verifiedAt
  ).length;

  // Presence lives in two RTDB nodes. `teachers/{uid}` is authoritative but the
  // app only writes `status` and `subjects` there — name, photo and `since` are
  // in the `onlineTeachers` projection the backend publishes (see
  // ./presence.ts). Read both so the console shows the same teachers students
  // see, and flags any teacher present in one node but not the other.
  const presenceRecords = (presenceSnap.val() ?? {}) as Record<string, Record<string, unknown>>;
  const onlineProjection = (onlineSnap.val() ?? {}) as Record<string, Record<string, unknown>>;

  const onlineUids = [
    ...new Set([
      ...Object.entries(presenceRecords)
        .filter(([, t]) => t?.status === "online")
        .map(([uid]) => uid),
      ...Object.keys(onlineProjection),
    ]),
  ];

  const [onlineUserDocs, onlineAggregates] = await Promise.all([
    onlineUids.length
      ? firestore.getAll(...onlineUids.map((uid) => firestore.collection("users").doc(uid)))
      : Promise.resolve([]),
    readTeacherAggregates(onlineUids),
  ]);
  const onlineUserMap = new Map(onlineUserDocs.map((d) => [d.id, d.data() ?? {}]));

  const onlineTeachers = onlineUids.map((uid) => {
    const presence = presenceRecords[uid] ?? {};
    const projected = onlineProjection[uid] ?? {};
    const user = onlineUserMap.get(uid) ?? {};
    const aggregate = onlineAggregates.get(uid);
    const projectedSubjects = Array.isArray(projected.subjects) ? (projected.subjects as string[]) : null;
    const presenceSubjects = Array.isArray(presence.subjects) ? (presence.subjects as string[]) : null;

    return {
      uid,
      displayName:
        firstString(projected.displayName, user.fullName, presence.displayName) ?? uid,
      photoUrl: firstString(
        projected.photoUrl,
        user.profileImageURL,
        user.profilePhotoURL,
        user.photoURL
      ),
      subjects: projectedSubjects ?? presenceSubjects ?? [],
      since: dateFieldToMs(projected.since),
      averageRate: aggregate?.averageRate ?? null,
      ratingCount: aggregate?.ratingCount ?? null,
      verified: Boolean(aggregate?.verifiedAt),
      // A teacher marked online whose projection is missing (or vice versa) is
      // invisible to students, or visible after going offline. Either way it
      // needs `adminRepublishOnlineTeachers`.
      presenceStatus: (presence.status as string) ?? null,
      published: uid in onlineProjection,
      stale: (presence.status === "online") !== (uid in onlineProjection),
    };
  });

  const rtdbQs = (rtdbQsSnap.val() ?? {}) as Record<string, Record<string, unknown>>;
  const rtdbQList = Object.entries(rtdbQs).map(([qid, q]) => ({
    qid,
    status: q.status,
    createdAt: dateFieldToMs(q.createdAt),
    topic: q.topic,
    studentUid: q.studentUid ?? q.userId,
  }));

  let oldestSearching: Record<string, unknown> | null = null;
  if (searchingCount.data().count > 0) {
    const snap = await firestore
      .collection("questions")
      .where("status", "==", "searching")
      .orderBy("createdAt", "asc")
      .limit(5)
      .get();
    if (!snap.empty) {
      const docs = snap.docs.map((d) => ({ id: d.id, ...serializeDoc(d.data()) }));
      oldestSearching = docs[0];
    }
  }

  const completedPaymentsSnap = await firestore
    .collection("paymentCheckouts")
    .where("status", "==", "completed")
    .get();

  const totalCentsByCurrency: Record<string, number> = {};
  let maxPaymentCents = 0;
  let maxPaymentId = "";
  const paymentValues: number[] = [];

  for (const d of completedPaymentsSnap.docs) {
    const c = (d.data().currency as string) || "USD";
    const cents = Number(d.data().priceCents) || 0;
    totalCentsByCurrency[c] = (totalCentsByCurrency[c] ?? 0) + cents;
    paymentValues.push(cents);
    if (cents > maxPaymentCents) { maxPaymentCents = cents; maxPaymentId = d.id; }
  }

  const avgPaymentCents = paymentValues.length
    ? Math.round(paymentValues.reduce((a, b) => a + b, 0) / paymentValues.length)
    : 0;

  const sortedCurrencies = Object.entries(totalCentsByCurrency).sort((a, b) => b[1] - a[1]);
  const revenueCurrency = sortedCurrencies[0]?.[0] ?? "USD";
  const totalRevenueCents = sortedCurrencies[0]?.[1] ?? 0;

  // A live lesson is worth showing with the people in it, so the row can be
  // acted on without copying UIDs into the users page.
  const activeLessonUids = [
    ...new Set(
      activeLessonsSnap.docs.flatMap((d) => {
        const data = d.data();
        return [data.studentUid, data.teacherUid].filter((v): v is string => typeof v === "string");
      })
    ),
  ];
  const activeLessonUserDocs = activeLessonUids.length
    ? await firestore.getAll(...activeLessonUids.map((uid) => firestore.collection("users").doc(uid)))
    : [];
  const lessonNameMap = new Map(
    activeLessonUserDocs.map((d) => [d.id, firstString(d.data()?.fullName) ?? null])
  );

  const activeLessons = activeLessonsSnap.docs.map((d) => {
    const data = serializeDoc(d.data());
    return {
      id: d.id,
      ...data,
      studentName: lessonNameMap.get(String(data.studentUid ?? "")) ?? null,
      teacherName: lessonNameMap.get(String(data.teacherUid ?? "")) ?? null,
    };
  });

  const platformStats = platformStatsSnap.exists
    ? serializeDoc(platformStatsSnap.data() as Record<string, unknown>)
    : null;

  return {
    pendingVerifications: pendingVerificationCount,
    teachers: {
      total: teacherUsersSnap.size,
      online: onlineTeachers.length,
      list: onlineTeachers,
      // Presence rows and published rows that disagree — see `stale` above.
      staleProjections: onlineTeachers.filter((t) => t.stale).length,
    },
    questions: {
      searching: searchingCount.data().count,
      accepted: acceptedCount.data().count,
      inProgress: inProgressCount.data().count,
      completed: completedCount.data().count,
      unanswered: unansweredCount.data().count,
      cancelled: cancelledCount.data().count,
      rtdbActive: rtdbQList.length,
      rtdbList: rtdbQList.slice(0, 20),
      oldestSearching,
    },
    lessons: {
      active: activeLessons,
    },
    users: {
      total: userCountSnap.data().count,
    },
    platform: platformStats,
    revenue: {
      totalCents: totalRevenueCents,
      currency: revenueCurrency,
      byCurrency: totalCentsByCurrency,
      completedPayments: completedPaymentsSnap.size,
      avgPaymentCents,
      maxPaymentCents,
      maxPaymentId,
    },
  };
});

// ─── adminListUsers ────────────────────────────────────────────────────────────

export const adminListUsers = onCall(async (req) => {
  assertAdmin(req);

  const { pageToken } = req.data as { pageToken?: string };

  const listResult = await admin.auth().listUsers(100, pageToken);

  const uids = listResult.users.map((u) => u.uid);
  const firestoreDocs = uids.length
    ? await firestore.getAll(...uids.map((uid) => firestore.collection("users").doc(uid)))
    : [];
  const fsMap = new Map(firestoreDocs.map((d) => [d.id, (d.data() ?? {}) as Record<string, unknown>]));

  const users = listResult.users.map((u) => {
    const fs = fsMap.get(u.uid) ?? {};
    return {
      uid: u.uid,
      email: u.email ?? null,
      displayName: firstString(fs.fullName, u.displayName),
      photoURL: firstString(fs.profileImageURL, fs.profilePhotoURL, fs.photoURL, u.photoURL),
      disabled: u.disabled,
      emailVerified: u.emailVerified,
      createdAt: u.metadata.creationTime ? new Date(u.metadata.creationTime).getTime() : null,
      lastSignIn: u.metadata.lastSignInTime ? new Date(u.metadata.lastSignInTime).getTime() : null,
      // `role` decides which columns mean anything: `remainingMinutes` is a
      // student's balance, `totalMinutes` a teacher's minutes taught.
      role: firstString(fs.role),
      currency: firstString(fs.currency),
      remainingMinutes: fs.remainingMinutes ?? 0,
      totalMinutes: fs.totalMinutes ?? 0,
      totalMinutesUsed: fs.totalMinutesUsed ?? null,
      // Major units of the user's own `currency`, not cents.
      totalEarnings: numberOrNull(fs.totalEarnings),
      hasProfile: fsMap.has(u.uid),
    };
  });

  return {
    users,
    nextPageToken: listResult.pageToken ?? null,
  };
});

// ─── adminGetUserDetail ────────────────────────────────────────────────────────

export const adminGetUserDetail = onCall(async (req) => {
  assertAdmin(req);

  const { uid } = req.data as { uid: string };
  if (!uid) throw new HttpsError("invalid-argument", "uid required");

  const [
    authUser,
    fsDoc,
    purchasesSnap,
    askedSnap,
    taughtSnap,
    teacherDocSnap,
    ratingsSnap,
    messagesSnap,
    presenceSnap,
    onlineSnap,
  ] = await Promise.all([
    admin.auth().getUser(uid),
    firestore.collection("users").doc(uid).get(),
    firestore.collection("users").doc(uid).collection("purchases").orderBy("purchasedAt", "desc").limit(20).get(),
    firestore
      .collection("questions")
      .where("studentUid", "==", uid)
      .orderBy("createdAt", "desc")
      .limit(20)
      .get(),
    // Lessons this user taught. `endLesson` writes `acceptedByTeacher` (and a
    // `teacherId` alias) onto the question, so a teacher's history lives here
    // rather than on the sparsely-written `lessons` collection.
    //
    // Degrades to an empty list rather than rejecting: this needs a composite
    // index (see firestore.indexes.json), and until that is deployed a missing
    // index must not take the whole user detail down with it.
    firestore
      .collection("questions")
      .where("acceptedByTeacher", "==", uid)
      .orderBy("createdAt", "desc")
      .limit(20)
      .get()
      .catch((err) => {
        logger.warn(`[admin] taught-questions query failed uid=${uid}`, err);
        return null;
      }),
    firestore.collection("teachers").doc(uid).get(),
    firestore.collection("teachers").doc(uid).collection("ratings").orderBy("endedAt", "desc").limit(10).get(),
    firestore.collection("users").doc(uid).collection("incomingMessages").orderBy("createdAt", "desc").limit(20).get(),
    db.ref(`teachers/${uid}`).once("value"),
    db.ref(`${ONLINE_TEACHERS_PATH}/${uid}`).once("value"),
  ]);

  const fsData = serializeDoc((fsDoc.data() ?? {}) as Record<string, unknown>);
  const purchases = purchasesSnap.docs.map((d) => ({ id: d.id, ...serializeDoc(d.data() as Record<string, unknown>) }));
  const questions = askedSnap.docs.map((d) =>
    normalizeQuestion(d.id, d.data() as Record<string, unknown>)
  );
  const taughtQuestions = (taughtSnap?.docs ?? []).map((d) =>
    normalizeQuestion(d.id, d.data() as Record<string, unknown>)
  );
  const ratings = ratingsSnap.docs.map((d) => ({ id: d.id, ...serializeDoc(d.data() as Record<string, unknown>) }));
  const messages = messagesSnap.docs.map((d) => ({ id: d.id, ...serializeDoc(d.data() as Record<string, unknown>) }));

  const teacherAggregate = teacherDocSnap.exists
    ? serializeDoc(teacherDocSnap.data() as Record<string, unknown>)
    : null;

  // RTDB presence, split the way it is actually stored: `teachers/{uid}` holds
  // only what the app writes, `onlineTeachers/{uid}` the published projection.
  const presence = presenceSnap.val();
  const onlineEntry = onlineSnap.val();

  return {
    auth: {
      uid: authUser.uid,
      email: authUser.email ?? null,
      displayName: authUser.displayName ?? null,
      photoURL: authUser.photoURL ?? null,
      disabled: authUser.disabled,
      emailVerified: authUser.emailVerified,
      providers: authUser.providerData.map((p) => p.providerId),
      createdAt: authUser.metadata.creationTime ? new Date(authUser.metadata.creationTime).getTime() : null,
      lastSignIn: authUser.metadata.lastSignInTime ? new Date(authUser.metadata.lastSignInTime).getTime() : null,
    },
    firestore: fsData,
    purchases,
    questions,
    taughtQuestions,
    teacherDoc: teacherAggregate,
    ratings,
    messages,
    presence: presence
      ? {
          status: (presence.status as string) ?? null,
          subjects: Array.isArray(presence.subjects) ? presence.subjects : [],
          hasFcmToken: Boolean(presence.fcmToken),
        }
      : null,
    onlineEntry: onlineEntry
      ? {
          displayName: (onlineEntry.displayName as string) ?? null,
          photoUrl: (onlineEntry.photoUrl as string) ?? null,
          subjects: Array.isArray(onlineEntry.subjects) ? onlineEntry.subjects : [],
          since: dateFieldToMs(onlineEntry.since),
        }
      : null,
  };
});

// ─── adminMutateUser ──────────────────────────────────────────────────────────

/**
 * Removes everything a deleted account leaves behind.
 *
 * Deleting only the auth account and `users/{uid}` used to leave the teacher
 * published in RTDB `onlineTeachers`, so the dispatcher kept inviting a user
 * who no longer existed, and left their purchases and inbox as orphaned
 * subcollections (deleting a document does not delete its subcollections).
 */
async function purgeUserData(uid: string): Promise<void> {
  const userRef = firestore.collection("users").doc(uid);

  for (const name of ["purchases", "incomingMessages", "generalMessages"]) {
    const snap = await userRef.collection(name).limit(500).get();
    if (snap.empty) continue;
    const batch = firestore.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }

  const ratingsSnap = await firestore.collection("teachers").doc(uid).collection("ratings").limit(500).get();
  if (!ratingsSnap.empty) {
    const batch = firestore.batch();
    ratingsSnap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }

  await Promise.all([
    userRef.delete(),
    firestore.collection("teachers").doc(uid).delete(),
    db.ref(`teachers/${uid}`).remove(),
    db.ref(`${ONLINE_TEACHERS_PATH}/${uid}`).remove(),
    db.ref(`teacherInvites/${uid}`).remove(),
    db.ref(`users/${uid}`).remove(),
  ]);
}

export const adminMutateUser = onCall(async (req) => {
  assertAdmin(req);

  const data = req.data as {
    action:
      | "delete"
      | "adjustMinutes"
      | "passwordResetLink"
      | "disable"
      | "enable"
      | "goOffline"
      | "setRole";
    uid: string;
    delta?: number;
    role?: string;
  };

  const { action, uid } = data;
  if (!uid) throw new HttpsError("invalid-argument", "uid required");

  logger.info(`[admin] mutateUser action=${action} uid=${uid} by=${req.auth?.token?.email}`);

  switch (action) {
    case "delete": {
      await admin.auth().deleteUser(uid);
      await purgeUserData(uid);
      logger.info(`[admin] deleted user uid=${uid}`);
      return { success: true };
    }

    case "adjustMinutes": {
      const delta = Number(data.delta);
      if (!Number.isFinite(delta)) throw new HttpsError("invalid-argument", "delta must be a number");
      await firestore.collection("users").doc(uid).set(
        { remainingMinutes: FieldValue.increment(delta) },
        { merge: true }
      );
      logger.info(`[admin] adjusted minutes uid=${uid} delta=${delta}`);
      return { success: true };
    }

    case "passwordResetLink": {
      const userRecord = await admin.auth().getUser(uid);
      if (!userRecord.email) throw new HttpsError("failed-precondition", "User has no email");
      const link = await admin.auth().generatePasswordResetLink(userRecord.email);
      logger.info(`[admin] generated password reset link uid=${uid}`);
      return { success: true, link };
    }

    case "disable": {
      await admin.auth().updateUser(uid, { disabled: true });
      logger.info(`[admin] disabled user uid=${uid}`);
      return { success: true };
    }

    case "enable": {
      await admin.auth().updateUser(uid, { disabled: false });
      logger.info(`[admin] enabled user uid=${uid}`);
      return { success: true };
    }

    // Signing a teacher out does not clear presence, so a demo (or stuck)
    // teacher keeps receiving dispatched questions until someone clears both
    // the authoritative node and the published projection.
    case "goOffline": {
      await db.ref(`teachers/${uid}/status`).set("offline");
      await db.ref(`${ONLINE_TEACHERS_PATH}/${uid}`).remove();
      logger.info(`[admin] forced teacher offline uid=${uid}`);
      return { success: true };
    }

    case "setRole": {
      const role = data.role;
      if (role !== "student" && role !== "teacher") {
        throw new HttpsError("invalid-argument", "role must be \"student\" or \"teacher\"");
      }
      await firestore.collection("users").doc(uid).set({ role }, { merge: true });
      logger.info(`[admin] set role uid=${uid} role=${role}`);
      return { success: true };
    }

    default:
      throw new HttpsError("invalid-argument", `Unknown action: ${action}`);
  }
});

// ─── adminListQuestions ────────────────────────────────────────────────────────

/**
 * Normalises one question for the console.
 *
 * The billing fields moved: `endLesson` writes `durationSeconds` plus `cost`
 * and `teacherEarnings` in major units of the question's own `currencyCode`.
 * The console used to read `billedSeconds` / `totalCents`, which only ever
 * existed on the `lessons` collection, so every completed question showed a
 * blank duration and a price in the wrong currency.
 */
function normalizeQuestion(id: string, raw: Record<string, unknown>): Record<string, unknown> {
  const data = serializeDoc(raw);
  const durationSeconds =
    numberOrNull(data.durationSeconds) ?? numberOrNull(data.billedSeconds);

  return {
    ...data,
    id,
    teacherUid: firstString(data.acceptedByTeacher, data.teacherId),
    durationSeconds,
    // Cents, in `currency` — never mixed with the dashboard's default.
    costCents: majorUnitsToCents(data.cost) ?? numberOrNull(data.totalCents),
    teacherEarningsCents: majorUnitsToCents(data.teacherEarnings),
    currency: firstString(data.currencyCode) ?? null,
    studentRating: numberOrNull(data.studentRating),
    text: firstString(data.text, data.questionText, data.originalQuestion, data.message) ?? "",
  };
}

export const adminListQuestions = onCall(async (req) => {
  assertAdmin(req);

  const { status, limit = 50, startAfter } = req.data as {
    status?: string;
    limit?: number;
    startAfter?: number;
  };

  const pageSize = Math.min(limit, 100);
  let query = firestore.collection("questions").orderBy("createdAt", "desc").limit(pageSize);

  if (status && status !== "all") {
    query = firestore
      .collection("questions")
      .where("status", "==", status)
      .orderBy("createdAt", "desc")
      .limit(pageSize);
  }

  if (startAfter) {
    query = query.startAfter(Timestamp.fromMillis(startAfter));
  }

  const snap = await query.get();
  const docs = snap.docs.map((d) => normalizeQuestion(d.id, d.data() as Record<string, unknown>));

  // Names, so a row reads as "Dana → Yossi" rather than two truncated UIDs.
  const uids = [
    ...new Set(
      docs.flatMap((q) => [q.studentUid, q.teacherUid].filter((v): v is string => typeof v === "string"))
    ),
  ];
  const userDocs = uids.length
    ? await firestore.getAll(...uids.map((uid) => firestore.collection("users").doc(uid)))
    : [];
  const nameMap = new Map(userDocs.map((d) => [d.id, firstString(d.data()?.fullName)]));

  const questions = docs.map((q) => ({
    ...q,
    studentName: firstString(q.studentName) ?? nameMap.get(String(q.studentUid ?? "")) ?? null,
    teacherName: nameMap.get(String(q.teacherUid ?? "")) ?? null,
  }));

  return { questions, hasMore: docs.length === pageSize };
});

// ─── adminListLessons ─────────────────────────────────────────────────────────

/**
 * The `lessons` collection: one document per lesson that actually connected,
 * with the pricing snapshot frozen at `startLesson` and the settlement written
 * at `endLesson`. Money here is in major units of `currencyCode`, like on
 * questions.
 */
export const adminListLessons = onCall(async (req) => {
  assertAdmin(req);

  const { status, limit = 50, startAfter } = req.data as {
    status?: string;
    limit?: number;
    startAfter?: number;
  };

  const pageSize = Math.min(limit, 100);
  let query = firestore.collection("lessons").orderBy("startedAt", "desc").limit(pageSize);

  if (status && status !== "all") {
    query = firestore
      .collection("lessons")
      .where("status", "==", status)
      .orderBy("startedAt", "desc")
      .limit(pageSize);
  }

  if (startAfter) {
    query = query.startAfter(Timestamp.fromMillis(startAfter));
  }

  const snap = await query.get();
  const rows: Record<string, unknown>[] = snap.docs.map((d) => {
    const data = serializeDoc(d.data() as Record<string, unknown>);
    return {
      ...data,
      id: d.id,
      durationSeconds: numberOrNull(data.durationSeconds) ?? numberOrNull(data.billedSeconds),
      costCents: majorUnitsToCents(data.cost) ?? numberOrNull(data.totalCents),
      teacherEarningsCents: majorUnitsToCents(data.teacherEarnings),
      currency: firstString(data.currencyCode) ?? null,
    };
  });

  const uids = [
    ...new Set(
      rows.flatMap((l) => [l.studentUid, l.teacherUid].filter((v): v is string => typeof v === "string"))
    ),
  ];
  const userDocs = uids.length
    ? await firestore.getAll(...uids.map((uid) => firestore.collection("users").doc(uid)))
    : [];
  const nameMap = new Map(userDocs.map((d) => [d.id, firstString(d.data()?.fullName)]));

  const lessons = rows.map((l) => ({
    ...l,
    studentName: nameMap.get(String(l.studentUid ?? "")) ?? null,
    teacherName: nameMap.get(String(l.teacherUid ?? "")) ?? null,
  }));

  return { lessons, hasMore: rows.length === pageSize };
});

// ─── adminListPricing ─────────────────────────────────────────────────────────

/** The `pricing` packages the payment flows read. World-readable, so worth
 *  being able to check what students are actually offered. */
export const adminListPricing = onCall(async (req) => {
  assertAdmin(req);

  const snap = await firestore.collection("pricing").get();
  const packages: Record<string, unknown>[] = snap.docs.map((d) => ({
    ...serializeDoc(d.data() as Record<string, unknown>),
    id: d.id,
  }));
  packages.sort((a, b) => Number(a.sortOrder ?? 0) - Number(b.sortOrder ?? 0));

  return { packages };
});

// ─── adminListCoupons ─────────────────────────────────────────────────────────

export const adminListCoupons = onCall(async (req) => {
  assertAdmin(req);

  const snap = await firestore.collection("coupons").orderBy("createdAt", "desc").get();
  const coupons = snap.docs.map((d) => ({ id: d.id, ...serializeDoc(d.data() as Record<string, unknown>) }));

  return { coupons };
});

// ─── adminCreateCoupon ────────────────────────────────────────────────────────

export const adminCreateCoupon = onCall(async (req) => {
  assertAdmin(req);

  const { studentUserId, numberOfMinutes, price, createdBy, couponId, applyDirectly } = req.data as {
    studentUserId: string;
    numberOfMinutes: number;
    price: number;
    createdBy: string;
    couponId?: string;
    applyDirectly?: boolean;
  };

  if (!studentUserId) throw new HttpsError("invalid-argument", "studentUserId required");
  if (!numberOfMinutes || numberOfMinutes <= 0) throw new HttpsError("invalid-argument", "numberOfMinutes must be positive");
  if (!createdBy) throw new HttpsError("invalid-argument", "createdBy required");

  const docId = couponId?.trim() || generateCouponCode();
  const ref = firestore.collection("coupons").doc(docId);
  const safePrice = Number(price);
  const normalizedPrice = Number.isFinite(safePrice) && safePrice >= 0 ? safePrice : 0;

  await firestore.runTransaction(async (tx) => {
    const existing = await tx.get(ref);
    if (existing.exists) throw new HttpsError("already-exists", `Coupon code "${docId}" already exists`);

    const now = Timestamp.now();

    tx.set(ref, {
      studentUserId,
      numberOfMinutes,
      price: normalizedPrice,
      createdBy,
      createdAt: now,
      activatedAt: applyDirectly ? now : null,
    });

    if (!applyDirectly) return;

    const userRef = firestore.collection("users").doc(studentUserId);
    tx.set(
      userRef,
      {
        remainingMinutes: FieldValue.increment(numberOfMinutes),
        totalMinutes: FieldValue.increment(numberOfMinutes),
      },
      { merge: true }
    );

    const purchaseRef = userRef.collection("purchases").doc(docId);
    tx.set(purchaseRef, {
      pricingOptionId: docId,
      provider: "coupon",
      amountCents: Math.round(normalizedPrice * 100),
      currency: "USD",
      type: "pay_as_you_go",
      status: "active",
      purchasedAt: now,
      updatedAt: now,
      minutesPurchased: numberOfMinutes,
      minutesRemaining: numberOfMinutes,
      minutesUsed: 0,
      createdBy,
    });
  });

  logger.info(`[admin] created coupon id=${docId} for uid=${studentUserId} minutes=${numberOfMinutes} applyDirectly=${Boolean(applyDirectly)}`);
  return { success: true, couponId: docId, appliedDirectly: Boolean(applyDirectly) };
});

function generateCouponCode(length = 8): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from({ length }, () => chars[Math.floor(Math.random() * chars.length)]).join("");
}

// ─── adminDeleteCoupon ────────────────────────────────────────────────────────

export const adminDeleteCoupon = onCall(async (req) => {
  assertAdmin(req);

  const { couponId } = req.data as { couponId: string };
  if (!couponId) throw new HttpsError("invalid-argument", "couponId required");

  const ref = firestore.collection("coupons").doc(couponId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Coupon not found");
  if (snap.data()?.activatedAt) throw new HttpsError("failed-precondition", "Cannot delete an activated coupon");

  await ref.delete();
  logger.info(`[admin] deleted coupon id=${couponId}`);
  return { success: true };
});

// ─── adminListPayments ────────────────────────────────────────────────────────

export const adminListPayments = onCall(async (req) => {
  assertAdmin(req);

  const { limit = 50, statusFilter } = req.data as { limit?: number; statusFilter?: string };

  const pageSize = Math.min(limit, 200);
  let query = firestore.collection("paymentCheckouts").orderBy("createdAt", "desc").limit(pageSize);

  if (statusFilter && statusFilter !== "all") {
    query = firestore
      .collection("paymentCheckouts")
      .where("status", "==", statusFilter)
      .orderBy("createdAt", "desc")
      .limit(pageSize);
  }

  const snap = await query.get();
  const payments = snap.docs.map((d) => {
    const data = serializeDoc(d.data() as Record<string, unknown>);
    // Checkout is no longer PayPal-only: Braintree handles Apple Pay, Google
    // Pay and cards, and a vaulted account charges without a redirect. Which
    // one ran is the difference between `paypalCaptureId` and
    // `braintreeTransactionId`; `paymentMethod` records the wallet the buyer
    // picked, and is absent on the plain PayPal flow.
    const provider = data.paypalCaptureId
      ? "paypal"
      : data.braintreeTransactionId
        ? "braintree"
        : data.paypalOrderId
          ? "paypal"
          : null;
    return {
      ...data,
      id: d.id,
      provider,
      paymentMethod: firstString(data.paymentMethod) ?? (provider === "paypal" ? "paypal" : null),
      transactionId: firstString(data.paypalCaptureId, data.braintreeTransactionId),
    };
  });

  return { payments };
});

// ─── adminListContactRequests ─────────────────────────────────────────────────

export const adminListContactRequests = onCall(async (req) => {
  assertAdmin(req);

  const snap = await firestore
    .collection("contactRequests")
    .orderBy("sentAt", "desc")
    .limit(100)
    .get();

  const requests = snap.docs.map((d) => {
    const data = d.data() as Record<string, unknown>;
    return {
      ...data,
      id: d.id,
      // Written by the client as an ISO-8601 string (see firestore.rules), so
      // it needs parsing rather than the Timestamp path.
      sentAtMs: dateFieldToMs(data.sentAt),
    };
  });
  return { requests };
});

// ─── adminListPendingTeachers ─────────────────────────────────────────────────

export const adminListPendingTeachers = onCall(async (req) => {
  assertAdmin(req);

  const teacherUsersSnap = await firestore.collection("users").where("role", "==", "teacher").get();
  const teachersWithDocs = teacherUsersSnap.docs.filter(
    (d) => ((d.data().uploadedDocuments as string[] | undefined) ?? []).length > 0
  );

  if (teachersWithDocs.length === 0) return { teachers: [] };

  const aggregates = await readTeacherAggregates(teachersWithDocs.map((d) => d.id));

  const results = await Promise.all(
    teachersWithDocs.map(async (d) => {
      const fsData = d.data();
      const authUser = await admin.auth().getUser(d.id).catch(() => null);
      const aggregate = aggregates.get(d.id);
      return {
        uid: d.id,
        email: authUser?.email ?? (fsData.email as string) ?? null,
        displayName: firstString(fsData.fullName, authUser?.displayName),
        photoURL: firstString(
          fsData.profileImageURL,
          fsData.profilePhotoURL,
          authUser?.photoURL
        ),
        uploadedDocuments: (fsData.uploadedDocuments as string[]) ?? [],
        // The app writes `createdAt` as an ISO-8601 string, not a Timestamp
        // (see UserProfile.firestoreData) — the old `instanceof Timestamp`
        // check meant this was always null.
        createdAt: dateFieldToMs(fsData.createdAt),
        phoneNumber: firstString(fsData.phoneNumber),
        subjectSelections: (fsData.subjectSelections as Record<string, string[]>) ?? {},
        averageRate: aggregate?.averageRate ?? null,
        ratingCount: aggregate?.ratingCount ?? null,
        isVerified: Boolean(aggregate?.verifiedAt),
      };
    })
  );

  const pending = results.filter((t) => !t.isVerified);
  logger.info(`[admin] listPendingTeachers returning ${pending.length} pending`);
  return { teachers: pending };
});

// ─── adminGetTeacherDocs ──────────────────────────────────────────────────────

export const adminGetTeacherDocs = onCall(async (req) => {
  assertAdmin(req);

  const { uid } = req.data as { uid: string };
  if (!uid) throw new HttpsError("invalid-argument", "uid required");

  const userDoc = await firestore.collection("users").doc(uid).get();
  if (!userDoc.exists) throw new HttpsError("not-found", "User not found");

  const uploadedDocuments = (userDoc.data()?.uploadedDocuments as string[]) ?? [];
  const bucket = admin.storage().bucket();

  const docs = await Promise.all(
    uploadedDocuments.map(async (docName) => {
      const file = bucket.file(`documents/${uid}/${docName}.jpg`);
      try {
        const [url] = await file.getSignedUrl({
          action: "read",
          expires: Date.now() + 3600 * 1000,
        });
        return { name: docName, url };
      } catch (e) {
        logger.warn(`[admin] failed to sign URL for ${uid}/${docName}: ${e}`);
        return { name: docName, url: null };
      }
    })
  );

  return { docs };
});

// ─── adminVerifyTeacher ───────────────────────────────────────────────────────

export const adminVerifyTeacher = onCall(async (req) => {
  assertAdmin(req);

  const { uid, verified = true } = req.data as { uid: string; verified?: boolean };
  if (!uid) throw new HttpsError("invalid-argument", "uid required");

  // `verifiedAt: null` rather than a field delete, so `isTeacherVerified` in
  // the app (which treats NSNull as unverified) reads it correctly.
  await firestore.collection("teachers").doc(uid).set(
    { verifiedAt: verified ? Timestamp.now() : null },
    { merge: true }
  );

  logger.info(
    `[admin] ${verified ? "verified" : "unverified"} teacher uid=${uid} by=${req.auth?.token?.email}`
  );
  return { success: true, verified };
});

// ─── adminSendTeacherMessage ──────────────────────────────────────────────────

export const adminSendTeacherMessage = onCall(async (req) => {
  assertAdmin(req);

  const { uid, title, text } = req.data as { uid: string; title: string; text: string };
  if (!uid) throw new HttpsError("invalid-argument", "uid required");
  if (!title?.trim() || !text?.trim()) throw new HttpsError("invalid-argument", "title and text required");

  // The app reads this inbox for students and teachers alike
  // (NotificationMessageService), so nothing here is teacher-specific.
  const msgRef = firestore.collection("users").doc(uid).collection("incomingMessages").doc();
  await msgRef.set({
    title: title.trim(),
    text: text.trim(),
    createdAt: Timestamp.now(),
    readTimestamp: null,
  });

  logger.info(`[admin] sent message to uid=${uid} title="${title}" by=${req.auth?.token?.email}`);
  return { success: true };
});
