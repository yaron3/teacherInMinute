import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

const firestore = admin.firestore();
const db = admin.database();

const ADMIN_EMAIL = process.env.ADMIN_EMAIL ?? "yaronj3@gmail.com";

function assertAdmin(req: CallableRequest): void {
  const email = req.auth?.token?.email;
  if (!email || email !== ADMIN_EMAIL) {
    throw new HttpsError("permission-denied", "Admin access required");
  }
}

function tsToMs(value: unknown): number | null {
  if (!value) return null;
  if (typeof value === "number") return value < 1e12 ? value * 1000 : value;
  const obj = value as Record<string, unknown>;
  if (typeof obj.toMillis === "function") return (obj as { toMillis: () => number }).toMillis();
  if (typeof obj._seconds === "number") return (obj._seconds as number) * 1000;
  if (typeof obj.seconds === "number") return (obj.seconds as number) * 1000;
  return null;
}

function serializeDoc(data: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(data)) {
    if (v instanceof Timestamp) {
      out[k] = v.toMillis();
    } else if (v && typeof v === "object" && !Array.isArray(v)) {
      const ms = tsToMs(v);
      out[k] = ms !== null ? ms : v;
    } else {
      out[k] = v;
    }
  }
  return out;
}

// ─── adminDashboardStatus ─────────────────────────────────────────────────────

export const adminDashboardStatus = onCall(async (req) => {
  assertAdmin(req);

  const [
    teachersSnap,
    rtdbQsSnap,
    searchingCount,
    inProgressCount,
    completedCount,
    unansweredCount,
    cancelledCount,
    userCountSnap,
    activeLessonsSnap,
    pendingTeacherUsersSnap,
  ] = await Promise.all([
    db.ref("teachers").once("value"),
    db.ref("questions").once("value"),
    firestore.collection("questions").where("status", "==", "searching").count().get(),
    firestore.collection("questions").where("status", "==", "in_progress").count().get(),
    firestore.collection("questions").where("status", "==", "completed").count().get(),
    firestore.collection("questions").where("status", "==", "unanswered").count().get(),
    firestore.collection("questions").where("status", "==", "cancelled").count().get(),
    firestore.collection("users").count().get(),
    firestore.collection("lessons").where("status", "==", "in_progress").get(),
    firestore.collection("users").where("role", "==", "teacher").get(),
  ]);

  // Count teachers who have uploaded docs but no verifiedAt in teachers/{uid}
  const teacherUidsWithDocs = pendingTeacherUsersSnap.docs
    .filter((d) => ((d.data().uploadedDocuments as string[] | undefined) ?? []).length > 0)
    .map((d) => d.id);

  let pendingVerificationCount = 0;
  if (teacherUidsWithDocs.length > 0) {
    const verifiedSnaps = await firestore.getAll(
      ...teacherUidsWithDocs.map((uid) => firestore.collection("teachers").doc(uid))
    );
    pendingVerificationCount = verifiedSnaps.filter((s) => !s.exists || !s.data()?.verifiedAt).length;
  }

  const allTeachers = (teachersSnap.val() ?? {}) as Record<string, Record<string, unknown>>;
  const teacherList = Object.entries(allTeachers).map(([uid, t]) => ({
    uid,
    displayName: (t.displayName as string) ?? uid,
    status: t.status,
    subjects: t.subjects ?? [],
    ratingAvg: t.ratingAvg ?? null,
    acceptRate: t.acceptRate ?? null,
    lastActiveAt: t.lastActiveAt ?? null,
    photoUrl: t.photoUrl ?? null,
  }));
  const onlineTeachers = teacherList.filter((t) => t.status === "online");

  const rtdbQs = (rtdbQsSnap.val() ?? {}) as Record<string, Record<string, unknown>>;
  const rtdbQList = Object.entries(rtdbQs).map(([qid, q]) => ({
    qid,
    status: q.status,
    createdAt: tsToMs(q.createdAt),
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

  const activeLessons = activeLessonsSnap.docs.map((d) => ({
    id: d.id,
    ...serializeDoc(d.data()),
  }));

  return {
    pendingVerifications: pendingVerificationCount,
    teachers: {
      total: teacherList.length,
      online: onlineTeachers.length,
      list: onlineTeachers,
    },
    questions: {
      searching: searchingCount.data().count,
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
  const fsMap = new Map(firestoreDocs.map((d) => [d.id, d.data() ?? {}]));

  const users = listResult.users.map((u) => {
    const fs = fsMap.get(u.uid) ?? {};
    return {
      uid: u.uid,
      email: u.email ?? null,
      displayName: u.displayName ?? null,
      photoURL: u.photoURL ?? null,
      disabled: u.disabled,
      emailVerified: u.emailVerified,
      createdAt: u.metadata.creationTime ? new Date(u.metadata.creationTime).getTime() : null,
      lastSignIn: u.metadata.lastSignInTime ? new Date(u.metadata.lastSignInTime).getTime() : null,
      remainingMinutes: (fs as Record<string, unknown>).remainingMinutes ?? 0,
      totalMinutes: (fs as Record<string, unknown>).totalMinutes ?? 0,
      totalEarnings: (fs as Record<string, unknown>).totalEarnings ?? null,
      totalMinutesUsed: (fs as Record<string, unknown>).totalMinutesUsed ?? null,
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

  const [authUser, fsDoc, purchasesSnap, questionsSnap, teacherRtdb] = await Promise.all([
    admin.auth().getUser(uid),
    firestore.collection("users").doc(uid).get(),
    firestore.collection("users").doc(uid).collection("purchases").orderBy("purchasedAt", "desc").limit(20).get(),
    firestore
      .collection("questions")
      .where("studentUid", "==", uid)
      .orderBy("createdAt", "desc")
      .limit(20)
      .get(),
    db.ref(`teachers/${uid}`).once("value"),
  ]);

  const fsData = serializeDoc((fsDoc.data() ?? {}) as Record<string, unknown>);
  const purchases = purchasesSnap.docs.map((d) => ({ id: d.id, ...serializeDoc(d.data() as Record<string, unknown>) }));
  const questions = questionsSnap.docs.map((d) => ({ id: d.id, ...serializeDoc(d.data() as Record<string, unknown>) }));
  const teacherRecord = teacherRtdb.val();

  return {
    auth: {
      uid: authUser.uid,
      email: authUser.email ?? null,
      displayName: authUser.displayName ?? null,
      photoURL: authUser.photoURL ?? null,
      disabled: authUser.disabled,
      emailVerified: authUser.emailVerified,
      createdAt: authUser.metadata.creationTime ? new Date(authUser.metadata.creationTime).getTime() : null,
      lastSignIn: authUser.metadata.lastSignInTime ? new Date(authUser.metadata.lastSignInTime).getTime() : null,
    },
    firestore: fsData,
    purchases,
    questions,
    teacherRecord,
  };
});

// ─── adminMutateUser ──────────────────────────────────────────────────────────

export const adminMutateUser = onCall(async (req) => {
  assertAdmin(req);

  const data = req.data as {
    action: "delete" | "adjustMinutes" | "passwordResetLink" | "disable" | "enable";
    uid: string;
    delta?: number;
  };

  const { action, uid } = data;
  if (!uid) throw new HttpsError("invalid-argument", "uid required");

  logger.info(`[admin] mutateUser action=${action} uid=${uid} by=${req.auth?.token?.email}`);

  switch (action) {
    case "delete": {
      await admin.auth().deleteUser(uid);
      await firestore.collection("users").doc(uid).delete();
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

    default:
      throw new HttpsError("invalid-argument", `Unknown action: ${action}`);
  }
});

// ─── adminListQuestions ────────────────────────────────────────────────────────

export const adminListQuestions = onCall(async (req) => {
  assertAdmin(req);

  const { status, limit = 50, startAfter } = req.data as {
    status?: string;
    limit?: number;
    startAfter?: number;
  };

  let query = firestore
    .collection("questions")
    .orderBy("createdAt", "desc")
    .limit(Math.min(limit, 100));

  if (status && status !== "all") {
    query = firestore
      .collection("questions")
      .where("status", "==", status)
      .orderBy("createdAt", "desc")
      .limit(Math.min(limit, 100));
  }

  if (startAfter) {
    const startTs = Timestamp.fromMillis(startAfter);
    query = query.startAfter(startTs);
  }

  const snap = await query.get();
  const docs = snap.docs.map((d) => ({ id: d.id, ...serializeDoc(d.data() as Record<string, unknown>) }));

  return { questions: docs, hasMore: docs.length === Math.min(limit, 100) };
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

  const { studentUserId, numberOfMinutes, price, createdBy, couponId } = req.data as {
    studentUserId: string;
    numberOfMinutes: number;
    price: number;
    createdBy: string;
    couponId?: string;
  };

  if (!studentUserId) throw new HttpsError("invalid-argument", "studentUserId required");
  if (!numberOfMinutes || numberOfMinutes <= 0) throw new HttpsError("invalid-argument", "numberOfMinutes must be positive");
  if (!createdBy) throw new HttpsError("invalid-argument", "createdBy required");

  const docId = couponId?.trim() || generateCouponCode();
  const ref = firestore.collection("coupons").doc(docId);
  const existing = await ref.get();
  if (existing.exists) throw new HttpsError("already-exists", `Coupon code "${docId}" already exists`);

  await ref.set({
    studentUserId,
    numberOfMinutes,
    price: price ?? 0,
    createdBy,
    createdAt: Timestamp.now(),
    activatedAt: null,
  });

  logger.info(`[admin] created coupon id=${docId} for uid=${studentUserId} minutes=${numberOfMinutes}`);
  return { success: true, couponId: docId };
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

  let query = firestore
    .collection("paymentCheckouts")
    .orderBy("createdAt", "desc")
    .limit(Math.min(limit, 200));

  if (statusFilter && statusFilter !== "all") {
    query = firestore
      .collection("paymentCheckouts")
      .where("status", "==", statusFilter)
      .orderBy("createdAt", "desc")
      .limit(Math.min(limit, 200));
  }

  const snap = await query.get();
  const payments = snap.docs.map((d) => ({ id: d.id, ...serializeDoc(d.data() as Record<string, unknown>) }));

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

  const requests = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
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

  const verifiedSnaps = await firestore.getAll(
    ...teachersWithDocs.map((d) => firestore.collection("teachers").doc(d.id))
  );
  const verifiedMap = new Map(verifiedSnaps.map((s) => [s.id, s.data()?.verifiedAt]));

  const results = await Promise.all(
    teachersWithDocs.map(async (d) => {
      const fsData = d.data();
      const authUser = await admin.auth().getUser(d.id).catch(() => null);
      return {
        uid: d.id,
        email: authUser?.email ?? (fsData.email as string) ?? null,
        displayName: (fsData.fullName as string) ?? authUser?.displayName ?? null,
        photoURL:
          (fsData.profileImageURL as string) ??
          (fsData.profilePhotoURL as string) ??
          authUser?.photoURL ??
          null,
        uploadedDocuments: (fsData.uploadedDocuments as string[]) ?? [],
        createdAt: fsData.createdAt instanceof Timestamp ? fsData.createdAt.toMillis() : null,
        subjectSelections: (fsData.subjectSelections as Record<string, string[]>) ?? {},
        isVerified: !!verifiedMap.get(d.id),
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

  const { uid } = req.data as { uid: string };
  if (!uid) throw new HttpsError("invalid-argument", "uid required");

  await firestore.collection("teachers").doc(uid).set(
    { verifiedAt: Timestamp.now() },
    { merge: true }
  );

  logger.info(`[admin] verified teacher uid=${uid} by=${req.auth?.token?.email}`);
  return { success: true };
});

// ─── adminSendTeacherMessage ──────────────────────────────────────────────────

export const adminSendTeacherMessage = onCall(async (req) => {
  assertAdmin(req);

  const { uid, title, text } = req.data as { uid: string; title: string; text: string };
  if (!uid) throw new HttpsError("invalid-argument", "uid required");
  if (!title?.trim() || !text?.trim()) throw new HttpsError("invalid-argument", "title and text required");

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
