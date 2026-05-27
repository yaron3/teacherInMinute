"use strict";
var _a;
Object.defineProperty(exports, "__esModule", { value: true });
exports.adminSendTeacherMessage = exports.adminVerifyTeacher = exports.adminGetTeacherDocs = exports.adminListPendingTeachers = exports.adminListContactRequests = exports.adminListPayments = exports.adminDeleteCoupon = exports.adminCreateCoupon = exports.adminListCoupons = exports.adminListQuestions = exports.adminMutateUser = exports.adminGetUserDetail = exports.adminListUsers = exports.adminDashboardStatus = void 0;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const firestore = admin.firestore();
const db = admin.database();
const ADMIN_EMAIL = (_a = process.env.ADMIN_EMAIL) !== null && _a !== void 0 ? _a : "yaronj3@gmail.com";
function assertAdmin(req) {
    var _a, _b;
    const email = (_b = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.token) === null || _b === void 0 ? void 0 : _b.email;
    if (!email || email !== ADMIN_EMAIL) {
        throw new https_1.HttpsError("permission-denied", "Admin access required");
    }
}
function tsToMs(value) {
    if (!value)
        return null;
    if (typeof value === "number")
        return value < 1e12 ? value * 1000 : value;
    const obj = value;
    if (typeof obj.toMillis === "function")
        return obj.toMillis();
    if (typeof obj._seconds === "number")
        return obj._seconds * 1000;
    if (typeof obj.seconds === "number")
        return obj.seconds * 1000;
    return null;
}
function serializeDoc(data) {
    const out = {};
    for (const [k, v] of Object.entries(data)) {
        if (v instanceof firestore_1.Timestamp) {
            out[k] = v.toMillis();
        }
        else if (v && typeof v === "object" && !Array.isArray(v)) {
            const ms = tsToMs(v);
            out[k] = ms !== null ? ms : v;
        }
        else {
            out[k] = v;
        }
    }
    return out;
}
// ─── adminDashboardStatus ─────────────────────────────────────────────────────
exports.adminDashboardStatus = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d, _e, _f, _g;
    assertAdmin(req);
    const [teachersSnap, rtdbQsSnap, searchingCount, inProgressCount, completedCount, unansweredCount, cancelledCount, userCountSnap, activeLessonsSnap, pendingTeacherUsersSnap,] = await Promise.all([
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
        .filter((d) => { var _a; return ((_a = d.data().uploadedDocuments) !== null && _a !== void 0 ? _a : []).length > 0; })
        .map((d) => d.id);
    let pendingVerificationCount = 0;
    if (teacherUidsWithDocs.length > 0) {
        const verifiedSnaps = await firestore.getAll(...teacherUidsWithDocs.map((uid) => firestore.collection("teachers").doc(uid)));
        pendingVerificationCount = verifiedSnaps.filter((s) => { var _a; return !s.exists || !((_a = s.data()) === null || _a === void 0 ? void 0 : _a.verifiedAt); }).length;
    }
    const allTeachers = ((_a = teachersSnap.val()) !== null && _a !== void 0 ? _a : {});
    const teacherList = Object.entries(allTeachers).map(([uid, t]) => {
        var _a, _b, _c, _d, _e, _f;
        return ({
            uid,
            displayName: (_a = t.displayName) !== null && _a !== void 0 ? _a : uid,
            status: t.status,
            subjects: (_b = t.subjects) !== null && _b !== void 0 ? _b : [],
            ratingAvg: (_c = t.ratingAvg) !== null && _c !== void 0 ? _c : null,
            acceptRate: (_d = t.acceptRate) !== null && _d !== void 0 ? _d : null,
            lastActiveAt: (_e = t.lastActiveAt) !== null && _e !== void 0 ? _e : null,
            photoUrl: (_f = t.photoUrl) !== null && _f !== void 0 ? _f : null,
        });
    });
    const onlineTeachers = teacherList.filter((t) => t.status === "online");
    const rtdbQs = ((_b = rtdbQsSnap.val()) !== null && _b !== void 0 ? _b : {});
    const rtdbQList = Object.entries(rtdbQs).map(([qid, q]) => {
        var _a;
        return ({
            qid,
            status: q.status,
            createdAt: tsToMs(q.createdAt),
            topic: q.topic,
            studentUid: (_a = q.studentUid) !== null && _a !== void 0 ? _a : q.userId,
        });
    });
    let oldestSearching = null;
    if (searchingCount.data().count > 0) {
        const snap = await firestore
            .collection("questions")
            .where("status", "==", "searching")
            .orderBy("createdAt", "asc")
            .limit(5)
            .get();
        if (!snap.empty) {
            const docs = snap.docs.map((d) => (Object.assign({ id: d.id }, serializeDoc(d.data()))));
            oldestSearching = docs[0];
        }
    }
    const completedPaymentsSnap = await firestore
        .collection("paymentCheckouts")
        .where("status", "==", "completed")
        .get();
    const totalCentsByCurrency = {};
    let maxPaymentCents = 0;
    let maxPaymentId = "";
    const paymentValues = [];
    for (const d of completedPaymentsSnap.docs) {
        const c = d.data().currency || "USD";
        const cents = Number(d.data().priceCents) || 0;
        totalCentsByCurrency[c] = ((_c = totalCentsByCurrency[c]) !== null && _c !== void 0 ? _c : 0) + cents;
        paymentValues.push(cents);
        if (cents > maxPaymentCents) {
            maxPaymentCents = cents;
            maxPaymentId = d.id;
        }
    }
    const avgPaymentCents = paymentValues.length
        ? Math.round(paymentValues.reduce((a, b) => a + b, 0) / paymentValues.length)
        : 0;
    const sortedCurrencies = Object.entries(totalCentsByCurrency).sort((a, b) => b[1] - a[1]);
    const revenueCurrency = (_e = (_d = sortedCurrencies[0]) === null || _d === void 0 ? void 0 : _d[0]) !== null && _e !== void 0 ? _e : "USD";
    const totalRevenueCents = (_g = (_f = sortedCurrencies[0]) === null || _f === void 0 ? void 0 : _f[1]) !== null && _g !== void 0 ? _g : 0;
    const activeLessons = activeLessonsSnap.docs.map((d) => (Object.assign({ id: d.id }, serializeDoc(d.data()))));
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
exports.adminListUsers = (0, https_1.onCall)(async (req) => {
    var _a;
    assertAdmin(req);
    const { pageToken } = req.data;
    const listResult = await admin.auth().listUsers(100, pageToken);
    const uids = listResult.users.map((u) => u.uid);
    const firestoreDocs = uids.length
        ? await firestore.getAll(...uids.map((uid) => firestore.collection("users").doc(uid)))
        : [];
    const fsMap = new Map(firestoreDocs.map((d) => { var _a; return [d.id, (_a = d.data()) !== null && _a !== void 0 ? _a : {}]; }));
    const users = listResult.users.map((u) => {
        var _a, _b, _c, _d, _e, _f, _g, _h;
        const fs = (_a = fsMap.get(u.uid)) !== null && _a !== void 0 ? _a : {};
        return {
            uid: u.uid,
            email: (_b = u.email) !== null && _b !== void 0 ? _b : null,
            displayName: (_c = u.displayName) !== null && _c !== void 0 ? _c : null,
            photoURL: (_d = u.photoURL) !== null && _d !== void 0 ? _d : null,
            disabled: u.disabled,
            emailVerified: u.emailVerified,
            createdAt: u.metadata.creationTime ? new Date(u.metadata.creationTime).getTime() : null,
            lastSignIn: u.metadata.lastSignInTime ? new Date(u.metadata.lastSignInTime).getTime() : null,
            remainingMinutes: (_e = fs.remainingMinutes) !== null && _e !== void 0 ? _e : 0,
            totalMinutes: (_f = fs.totalMinutes) !== null && _f !== void 0 ? _f : 0,
            totalEarnings: (_g = fs.totalEarnings) !== null && _g !== void 0 ? _g : null,
            totalMinutesUsed: (_h = fs.totalMinutesUsed) !== null && _h !== void 0 ? _h : null,
        };
    });
    return {
        users,
        nextPageToken: (_a = listResult.pageToken) !== null && _a !== void 0 ? _a : null,
    };
});
// ─── adminGetUserDetail ────────────────────────────────────────────────────────
exports.adminGetUserDetail = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d;
    assertAdmin(req);
    const { uid } = req.data;
    if (!uid)
        throw new https_1.HttpsError("invalid-argument", "uid required");
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
    const fsData = serializeDoc(((_a = fsDoc.data()) !== null && _a !== void 0 ? _a : {}));
    const purchases = purchasesSnap.docs.map((d) => (Object.assign({ id: d.id }, serializeDoc(d.data()))));
    const questions = questionsSnap.docs.map((d) => (Object.assign({ id: d.id }, serializeDoc(d.data()))));
    const teacherRecord = teacherRtdb.val();
    return {
        auth: {
            uid: authUser.uid,
            email: (_b = authUser.email) !== null && _b !== void 0 ? _b : null,
            displayName: (_c = authUser.displayName) !== null && _c !== void 0 ? _c : null,
            photoURL: (_d = authUser.photoURL) !== null && _d !== void 0 ? _d : null,
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
exports.adminMutateUser = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    assertAdmin(req);
    const data = req.data;
    const { action, uid } = data;
    if (!uid)
        throw new https_1.HttpsError("invalid-argument", "uid required");
    firebase_functions_1.logger.info(`[admin] mutateUser action=${action} uid=${uid} by=${(_b = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.token) === null || _b === void 0 ? void 0 : _b.email}`);
    switch (action) {
        case "delete": {
            await admin.auth().deleteUser(uid);
            await firestore.collection("users").doc(uid).delete();
            firebase_functions_1.logger.info(`[admin] deleted user uid=${uid}`);
            return { success: true };
        }
        case "adjustMinutes": {
            const delta = Number(data.delta);
            if (!Number.isFinite(delta))
                throw new https_1.HttpsError("invalid-argument", "delta must be a number");
            await firestore.collection("users").doc(uid).set({ remainingMinutes: firestore_1.FieldValue.increment(delta) }, { merge: true });
            firebase_functions_1.logger.info(`[admin] adjusted minutes uid=${uid} delta=${delta}`);
            return { success: true };
        }
        case "passwordResetLink": {
            const userRecord = await admin.auth().getUser(uid);
            if (!userRecord.email)
                throw new https_1.HttpsError("failed-precondition", "User has no email");
            const link = await admin.auth().generatePasswordResetLink(userRecord.email);
            firebase_functions_1.logger.info(`[admin] generated password reset link uid=${uid}`);
            return { success: true, link };
        }
        case "disable": {
            await admin.auth().updateUser(uid, { disabled: true });
            firebase_functions_1.logger.info(`[admin] disabled user uid=${uid}`);
            return { success: true };
        }
        case "enable": {
            await admin.auth().updateUser(uid, { disabled: false });
            firebase_functions_1.logger.info(`[admin] enabled user uid=${uid}`);
            return { success: true };
        }
        default:
            throw new https_1.HttpsError("invalid-argument", `Unknown action: ${action}`);
    }
});
// ─── adminListQuestions ────────────────────────────────────────────────────────
exports.adminListQuestions = (0, https_1.onCall)(async (req) => {
    assertAdmin(req);
    const { status, limit = 50, startAfter } = req.data;
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
        const startTs = firestore_1.Timestamp.fromMillis(startAfter);
        query = query.startAfter(startTs);
    }
    const snap = await query.get();
    const docs = snap.docs.map((d) => (Object.assign({ id: d.id }, serializeDoc(d.data()))));
    return { questions: docs, hasMore: docs.length === Math.min(limit, 100) };
});
// ─── adminListCoupons ─────────────────────────────────────────────────────────
exports.adminListCoupons = (0, https_1.onCall)(async (req) => {
    assertAdmin(req);
    const snap = await firestore.collection("coupons").orderBy("createdAt", "desc").get();
    const coupons = snap.docs.map((d) => (Object.assign({ id: d.id }, serializeDoc(d.data()))));
    return { coupons };
});
// ─── adminCreateCoupon ────────────────────────────────────────────────────────
exports.adminCreateCoupon = (0, https_1.onCall)(async (req) => {
    assertAdmin(req);
    const { studentUserId, numberOfMinutes, price, createdBy, couponId } = req.data;
    if (!studentUserId)
        throw new https_1.HttpsError("invalid-argument", "studentUserId required");
    if (!numberOfMinutes || numberOfMinutes <= 0)
        throw new https_1.HttpsError("invalid-argument", "numberOfMinutes must be positive");
    if (!createdBy)
        throw new https_1.HttpsError("invalid-argument", "createdBy required");
    const docId = (couponId === null || couponId === void 0 ? void 0 : couponId.trim()) || generateCouponCode();
    const ref = firestore.collection("coupons").doc(docId);
    const existing = await ref.get();
    if (existing.exists)
        throw new https_1.HttpsError("already-exists", `Coupon code "${docId}" already exists`);
    await ref.set({
        studentUserId,
        numberOfMinutes,
        price: price !== null && price !== void 0 ? price : 0,
        createdBy,
        createdAt: firestore_1.Timestamp.now(),
        activatedAt: null,
    });
    firebase_functions_1.logger.info(`[admin] created coupon id=${docId} for uid=${studentUserId} minutes=${numberOfMinutes}`);
    return { success: true, couponId: docId };
});
function generateCouponCode(length = 8) {
    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    return Array.from({ length }, () => chars[Math.floor(Math.random() * chars.length)]).join("");
}
// ─── adminDeleteCoupon ────────────────────────────────────────────────────────
exports.adminDeleteCoupon = (0, https_1.onCall)(async (req) => {
    var _a;
    assertAdmin(req);
    const { couponId } = req.data;
    if (!couponId)
        throw new https_1.HttpsError("invalid-argument", "couponId required");
    const ref = firestore.collection("coupons").doc(couponId);
    const snap = await ref.get();
    if (!snap.exists)
        throw new https_1.HttpsError("not-found", "Coupon not found");
    if ((_a = snap.data()) === null || _a === void 0 ? void 0 : _a.activatedAt)
        throw new https_1.HttpsError("failed-precondition", "Cannot delete an activated coupon");
    await ref.delete();
    firebase_functions_1.logger.info(`[admin] deleted coupon id=${couponId}`);
    return { success: true };
});
// ─── adminListPayments ────────────────────────────────────────────────────────
exports.adminListPayments = (0, https_1.onCall)(async (req) => {
    assertAdmin(req);
    const { limit = 50, statusFilter } = req.data;
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
    const payments = snap.docs.map((d) => (Object.assign({ id: d.id }, serializeDoc(d.data()))));
    return { payments };
});
// ─── adminListContactRequests ─────────────────────────────────────────────────
exports.adminListContactRequests = (0, https_1.onCall)(async (req) => {
    assertAdmin(req);
    const snap = await firestore
        .collection("contactRequests")
        .orderBy("sentAt", "desc")
        .limit(100)
        .get();
    const requests = snap.docs.map((d) => (Object.assign({ id: d.id }, d.data())));
    return { requests };
});
// ─── adminListPendingTeachers ─────────────────────────────────────────────────
exports.adminListPendingTeachers = (0, https_1.onCall)(async (req) => {
    assertAdmin(req);
    const teacherUsersSnap = await firestore.collection("users").where("role", "==", "teacher").get();
    const teachersWithDocs = teacherUsersSnap.docs.filter((d) => { var _a; return ((_a = d.data().uploadedDocuments) !== null && _a !== void 0 ? _a : []).length > 0; });
    if (teachersWithDocs.length === 0)
        return { teachers: [] };
    const verifiedSnaps = await firestore.getAll(...teachersWithDocs.map((d) => firestore.collection("teachers").doc(d.id)));
    const verifiedMap = new Map(verifiedSnaps.map((s) => { var _a; return [s.id, (_a = s.data()) === null || _a === void 0 ? void 0 : _a.verifiedAt]; }));
    const results = await Promise.all(teachersWithDocs.map(async (d) => {
        var _a, _b, _c, _d, _e, _f, _g, _h, _j;
        const fsData = d.data();
        const authUser = await admin.auth().getUser(d.id).catch(() => null);
        return {
            uid: d.id,
            email: (_b = (_a = authUser === null || authUser === void 0 ? void 0 : authUser.email) !== null && _a !== void 0 ? _a : fsData.email) !== null && _b !== void 0 ? _b : null,
            displayName: (_d = (_c = fsData.fullName) !== null && _c !== void 0 ? _c : authUser === null || authUser === void 0 ? void 0 : authUser.displayName) !== null && _d !== void 0 ? _d : null,
            photoURL: (_g = (_f = (_e = fsData.profileImageURL) !== null && _e !== void 0 ? _e : fsData.profilePhotoURL) !== null && _f !== void 0 ? _f : authUser === null || authUser === void 0 ? void 0 : authUser.photoURL) !== null && _g !== void 0 ? _g : null,
            uploadedDocuments: (_h = fsData.uploadedDocuments) !== null && _h !== void 0 ? _h : [],
            createdAt: fsData.createdAt instanceof firestore_1.Timestamp ? fsData.createdAt.toMillis() : null,
            subjectSelections: (_j = fsData.subjectSelections) !== null && _j !== void 0 ? _j : {},
            isVerified: !!verifiedMap.get(d.id),
        };
    }));
    const pending = results.filter((t) => !t.isVerified);
    firebase_functions_1.logger.info(`[admin] listPendingTeachers returning ${pending.length} pending`);
    return { teachers: pending };
});
// ─── adminGetTeacherDocs ──────────────────────────────────────────────────────
exports.adminGetTeacherDocs = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    assertAdmin(req);
    const { uid } = req.data;
    if (!uid)
        throw new https_1.HttpsError("invalid-argument", "uid required");
    const userDoc = await firestore.collection("users").doc(uid).get();
    if (!userDoc.exists)
        throw new https_1.HttpsError("not-found", "User not found");
    const uploadedDocuments = (_b = (_a = userDoc.data()) === null || _a === void 0 ? void 0 : _a.uploadedDocuments) !== null && _b !== void 0 ? _b : [];
    const bucket = admin.storage().bucket();
    const docs = await Promise.all(uploadedDocuments.map(async (docName) => {
        const file = bucket.file(`documents/${uid}/${docName}.jpg`);
        try {
            const [url] = await file.getSignedUrl({
                action: "read",
                expires: Date.now() + 3600 * 1000,
            });
            return { name: docName, url };
        }
        catch (e) {
            firebase_functions_1.logger.warn(`[admin] failed to sign URL for ${uid}/${docName}: ${e}`);
            return { name: docName, url: null };
        }
    }));
    return { docs };
});
// ─── adminVerifyTeacher ───────────────────────────────────────────────────────
exports.adminVerifyTeacher = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    assertAdmin(req);
    const { uid } = req.data;
    if (!uid)
        throw new https_1.HttpsError("invalid-argument", "uid required");
    await firestore.collection("teachers").doc(uid).set({ verifiedAt: firestore_1.Timestamp.now() }, { merge: true });
    firebase_functions_1.logger.info(`[admin] verified teacher uid=${uid} by=${(_b = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.token) === null || _b === void 0 ? void 0 : _b.email}`);
    return { success: true };
});
// ─── adminSendTeacherMessage ──────────────────────────────────────────────────
exports.adminSendTeacherMessage = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    assertAdmin(req);
    const { uid, title, text } = req.data;
    if (!uid)
        throw new https_1.HttpsError("invalid-argument", "uid required");
    if (!(title === null || title === void 0 ? void 0 : title.trim()) || !(text === null || text === void 0 ? void 0 : text.trim()))
        throw new https_1.HttpsError("invalid-argument", "title and text required");
    const msgRef = firestore.collection("users").doc(uid).collection("incomingMessages").doc();
    await msgRef.set({
        title: title.trim(),
        text: text.trim(),
        createdAt: firestore_1.Timestamp.now(),
        readTimestamp: null,
    });
    firebase_functions_1.logger.info(`[admin] sent message to uid=${uid} title="${title}" by=${(_b = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.token) === null || _b === void 0 ? void 0 : _b.email}`);
    return { success: true };
});
//# sourceMappingURL=admin.js.map