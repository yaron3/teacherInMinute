import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";

import { CouponDoc } from "./types";

const firestore = admin.firestore();

function toSafeMinutes(value: unknown): number {
  const n = Math.floor(Number(value));
  return Number.isFinite(n) && n > 0 ? n : 0;
}

export const redeemCoupon = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const data = req.data as Record<string, unknown>;
  const couponId = data.couponCode as string | undefined;
  if (!couponId?.trim()) throw new HttpsError("invalid-argument", "Missing coupon code");

  logger.info(`[coupons] redeemCoupon uid=${uid} couponId=${couponId}`);

  const couponRef = firestore.collection("coupons").doc(couponId.trim());
  const couponSnap = await couponRef.get();

  if (!couponSnap.exists) {
    logger.info(`[coupons] coupon not found couponId=${couponId}`);
    throw new HttpsError("not-found", "Invalid coupon");
  }

  const coupon = couponSnap.data() as CouponDoc;

  if (coupon.studentUserId !== uid) {
    logger.info(`[coupons] coupon owner mismatch couponId=${couponId} owner=${coupon.studentUserId} requester=${uid}`);
    throw new HttpsError("not-found", "Invalid coupon");
  }

  if (coupon.activatedAt) {
    const activatedDate = coupon.activatedAt.toDate().toLocaleString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
    logger.info(`[coupons] coupon already activated couponId=${couponId} activatedAt=${activatedDate}`);
    throw new HttpsError("failed-precondition", `Coupon was already activated at: ${activatedDate}`);
  }

  const minutes = toSafeMinutes(coupon.numberOfMinutes);
  if (minutes <= 0) throw new HttpsError("internal", "Coupon has invalid minutes");

  const userRef = firestore.collection("users").doc(uid);

  await firestore.runTransaction(async (tx) => {
    const freshSnap = await tx.get(couponRef);
    if ((freshSnap.data() as CouponDoc | undefined)?.activatedAt) {
      throw new HttpsError("failed-precondition", "Coupon was already activated");
    }

    const now = Timestamp.now();

    tx.update(couponRef, { activatedAt: now });

    tx.set(
      userRef,
      {
        remainingMinutes: FieldValue.increment(minutes),
        totalMinutes: FieldValue.increment(minutes),
      },
      { merge: true }
    );

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

  logger.info(`[coupons] redeemCoupon success uid=${uid} couponId=${couponId} minutes=${minutes}`);
  return { success: true, minutesAdded: minutes };
});
