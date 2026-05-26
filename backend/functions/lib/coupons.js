"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.redeemCoupon = void 0;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const firestore = admin.firestore();
function toSafeMinutes(value) {
    const n = Math.floor(Number(value));
    return Number.isFinite(n) && n > 0 ? n : 0;
}
exports.redeemCoupon = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const data = req.data;
    const couponId = data.couponCode;
    if (!(couponId === null || couponId === void 0 ? void 0 : couponId.trim()))
        throw new https_1.HttpsError("invalid-argument", "Missing coupon code");
    firebase_functions_1.logger.info(`[coupons] redeemCoupon uid=${uid} couponId=${couponId}`);
    const couponRef = firestore.collection("coupons").doc(couponId.trim());
    const couponSnap = await couponRef.get();
    if (!couponSnap.exists) {
        firebase_functions_1.logger.info(`[coupons] coupon not found couponId=${couponId}`);
        throw new https_1.HttpsError("not-found", "Invalid coupon");
    }
    const coupon = couponSnap.data();
    if (coupon.studentUserId !== uid) {
        firebase_functions_1.logger.info(`[coupons] coupon owner mismatch couponId=${couponId} owner=${coupon.studentUserId} requester=${uid}`);
        throw new https_1.HttpsError("not-found", "Invalid coupon");
    }
    if (coupon.activatedAt) {
        const activatedDate = coupon.activatedAt.toDate().toLocaleString("en-US", {
            year: "numeric",
            month: "long",
            day: "numeric",
            hour: "2-digit",
            minute: "2-digit",
        });
        firebase_functions_1.logger.info(`[coupons] coupon already activated couponId=${couponId} activatedAt=${activatedDate}`);
        throw new https_1.HttpsError("failed-precondition", `Coupon was already activated at: ${activatedDate}`);
    }
    const minutes = toSafeMinutes(coupon.numberOfMinutes);
    if (minutes <= 0)
        throw new https_1.HttpsError("internal", "Coupon has invalid minutes");
    const userRef = firestore.collection("users").doc(uid);
    await firestore.runTransaction(async (tx) => {
        var _a;
        const freshSnap = await tx.get(couponRef);
        if ((_a = freshSnap.data()) === null || _a === void 0 ? void 0 : _a.activatedAt) {
            throw new https_1.HttpsError("failed-precondition", "Coupon was already activated");
        }
        const now = firestore_1.Timestamp.now();
        tx.update(couponRef, { activatedAt: now });
        tx.set(userRef, {
            remainingMinutes: firestore_1.FieldValue.increment(minutes),
            totalMinutes: firestore_1.FieldValue.increment(minutes),
        }, { merge: true });
        const purchaseRef = userRef.collection("purchases").doc(couponId.trim());
        tx.set(purchaseRef, {
            pricingOptionId: couponId.trim(),
            provider: "coupon",
            amountCents: Math.round(coupon.price * 100),
            currency: "USD",
            type: "pay_as_you_go",
            status: "active",
            purchasedAt: now,
            updatedAt: now,
            minutesPurchased: minutes,
            minutesRemaining: minutes,
            minutesUsed: 0,
            createdBy: coupon.createdBy,
        });
    });
    firebase_functions_1.logger.info(`[coupons] redeemCoupon success uid=${uid} couponId=${couponId} minutes=${minutes}`);
    return { success: true, minutesAdded: minutes };
});
//# sourceMappingURL=coupons.js.map