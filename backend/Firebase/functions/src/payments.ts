import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { v4 as uuidv4 } from "uuid";

import { createOrder, captureOrder, verifyWebhookSignature, PaymentSource } from "./paypal";
import { createBitOrder, BitNotConfiguredError } from "./bit";
import {
  generateApplePayClientToken,
  createBraintreeSale,
  BraintreeNotConfiguredError,
  BraintreeCurrencyNotSupportedError,
} from "./braintree";
import { PricingDoc, PaymentCheckoutDoc, PurchaseDoc } from "./types";

const firestore = admin.firestore();

const FUNCTIONS_BASE_URL =
  "https://us-central1-teacher-in-a-moment.cloudfunctions.net";

/** Coerce a value from Firestore (may be string, number, null, undefined) to a safe integer. */
function toSafeMinutes(value: unknown): number {
  const n = Math.floor(Number(value));
  return Number.isFinite(n) && n > 0 ? n : 0;
}

/** Look up a pricing package and create its `paymentCheckouts` doc. Shared by every checkout entry point. */
async function resolvePricingAndCreateCheckout(params: {
  uid: string;
  packageId: string;
  paymentMethod?: string;
}): Promise<{
  checkoutId: string;
  checkoutRef: FirebaseFirestore.DocumentReference;
  pkg: PricingDoc & { priceCents: number };
}> {
  const packageSnap = await firestore.collection("pricing").doc(params.packageId).get();
  if (!packageSnap.exists) throw new HttpsError("not-found", "Pricing package not found");

  const pkg = packageSnap.data() as PricingDoc;
  const minutes = toSafeMinutes(pkg.minutes ?? pkg.minutesGranted);
  // Coerce to number — Firestore may return string if field was set via console
  const priceCents = Math.floor(Number(pkg.priceCents));

  if (!priceCents || priceCents <= 0)
    throw new HttpsError("internal", "Invalid package price");
  if (!pkg.currency)
    throw new HttpsError("internal", "Invalid package currency");
  if (minutes <= 0)
    throw new HttpsError("internal", "Invalid package minutes");

  logger.info(
    `[payments] package fetched packageId=${params.packageId} priceCents=${priceCents} currency=${pkg.currency} minutes=${minutes}`
  );

  const checkoutId = uuidv4();
  const checkoutRef = firestore.collection("paymentCheckouts").doc(checkoutId);
  const checkoutDoc: PaymentCheckoutDoc = {
    uid: params.uid,
    packageId: params.packageId,
    packageType: pkg.type,
    priceCents,
    currency: pkg.currency,
    minutes,
    status: "created",
    createdAt: Timestamp.now(),
    paypalOrderId: null,
    // Omit rather than write `undefined` — the plain-PayPal flow sends no
    // wallet, and Firestore rejects undefined field values.
    ...(params.paymentMethod ? { paymentMethod: params.paymentMethod } : {}),
  };
  await checkoutRef.set(checkoutDoc);

  return { checkoutId, checkoutRef, pkg: { ...pkg, priceCents } };
}

/**
 * Credit a completed checkout's minutes to the buyer and record the purchase.
 * Idempotent — safe to call from multiple completion paths (redirect return,
 * webhook, direct confirm) racing on the same checkout.
 */
async function creditCompletedCheckout(params: {
  checkoutRef: FirebaseFirestore.DocumentReference;
  checkout: PaymentCheckoutDoc;
  checkoutId: string;
  provider: PurchaseDoc["provider"];
  providerTransactionId: string;
  extraCheckoutFields?: Record<string, unknown>;
}): Promise<void> {
  const userRef = firestore.collection("users").doc(params.checkout.uid);

  await firestore.runTransaction(async (tx) => {
    const freshSnap = await tx.get(params.checkoutRef);
    if (freshSnap.data()?.status === "completed") return;

    const now = Timestamp.now();
    tx.update(params.checkoutRef, {
      status: "completed",
      completedAt: now,
      updatedAt: now,
      ...(params.provider === "paypal"
        ? { paypalCaptureId: params.providerTransactionId }
        : { braintreeTransactionId: params.providerTransactionId }),
      ...params.extraCheckoutFields,
    });
    tx.set(
      userRef,
      {
        remainingMinutes: FieldValue.increment(toSafeMinutes(params.checkout.minutes)),
        totalMinutes: FieldValue.increment(toSafeMinutes(params.checkout.minutes)),
      },
      { merge: true }
    );

    const purchaseRef = userRef.collection("purchases").doc(params.checkoutId);
    tx.set(
      purchaseRef,
      {
        pricingOptionId: params.checkout.packageId,
        provider: params.provider,
        amountCents: params.checkout.priceCents,
        currency: params.checkout.currency,
        type: params.checkout.packageType ?? "pay_as_you_go",
        status: "active",
        purchasedAt: now,
        updatedAt: now,
        minutesPurchased: toSafeMinutes(params.checkout.minutes),
        minutesRemaining: toSafeMinutes(params.checkout.minutes),
        minutesUsed: 0,
      },
      { merge: true }
    );
  });
}

// ─── createCheckoutSession ────────────────────────────────────────────────────

export const createCheckoutSession = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const data = req.data as Record<string, unknown>;
  const packageId = (
    data.pricingOptionId ??
    data.pricingOptionID ??
    data.packageId ??
    data.packageID ??
    data.pricingOption
  ) as string | undefined;

  logger.info(
    `[payments] createCheckoutSession uid=${uid} packageId=${packageId ?? "(missing)"}`
  );

  if (!packageId) throw new HttpsError("invalid-argument", "Missing pricing package id");

  const rawWallet = (data.paymentMethod ?? data.preferredPaymentMethod ?? data.wallet) as string | undefined;
  const rawPlatform = data.platform as string | undefined;
  const SUPPORTED_WALLETS = ["apple_pay", "google_pay", "credit_card", "bit"] as const;
  let paypalSource: PaymentSource = "paypal";
  if (rawWallet !== undefined) {
    if (!(SUPPORTED_WALLETS as readonly string[]).includes(rawWallet)) {
      throw new HttpsError("invalid-argument", `Unsupported paymentMethod "${rawWallet}"`);
    }
    if (rawWallet === "apple_pay" && rawPlatform === "android") {
      throw new HttpsError("invalid-argument", "Apple Pay is not supported on Android");
    }
    if (rawWallet === "apple_pay") {
      // Apple Pay needs a native PassKit sheet, which this PayPal Orders v2
      // integration cannot drive — see createApplePayCheckout below.
      throw new HttpsError(
        "failed-precondition",
        "Apple Pay checkout uses a separate flow — call createApplePayCheckout instead."
      );
    } else if (rawWallet === "google_pay") {
      paypalSource = "google_pay";
    } else if (rawWallet === "credit_card") {
      paypalSource = "card";
    }
    // "bit" has no PayPal payment_source — it's routed to a separate provider below.
  }

  const { checkoutId, checkoutRef, pkg } = await resolvePricingAndCreateCheckout({
    uid,
    packageId,
    paymentMethod: rawWallet,
  });
  const returnUrl = `${FUNCTIONS_BASE_URL}/paypalSuccess?checkoutId=${checkoutId}`;
  const cancelUrl = `${FUNCTIONS_BASE_URL}/paypalCancel?checkoutId=${checkoutId}`;

  if (rawWallet === "bit") {
    try {
      await createBitOrder({
        amountCents: pkg.priceCents,
        currency: pkg.currency,
        description: pkg.name,
        uid,
        sessionId: checkoutId,
        returnUrl,
        cancelUrl,
      });
    } catch (err) {
      await checkoutRef.update({ status: "cancelled", updatedAt: Timestamp.now() });
      if (err instanceof BitNotConfiguredError) {
        logger.warn(`[payments] Bit checkout requested but no provider is configured checkoutId=${checkoutId}`);
        throw new HttpsError(
          "failed-precondition",
          "Bit payments are not available yet. Please choose another payment method."
        );
      }
      logger.error(`[payments] Bit createOrder failed checkoutId=${checkoutId}`, err);
      throw new HttpsError("internal", "Failed to start Bit checkout");
    }
    // createBitOrder always throws while unconfigured — unreachable until a
    // real provider call replaces the stub in ./bit.ts.
    throw new HttpsError("internal", "Bit checkout did not return a URL");
  }

  let order;
  try {
    logger.info(
      `[payments] PayPal createOrder checkoutId=${checkoutId} amount=${(pkg.priceCents / 100).toFixed(2)} ${pkg.currency}`
    );
    order = await createOrder({
      amountCents: pkg.priceCents,
      currency: pkg.currency,
      description: pkg.name,
      uid,
      sessionId: checkoutId,
      returnUrl,
      cancelUrl,
      paymentSource: paypalSource,
    });
  } catch (err) {
    logger.error(`[payments] PayPal createOrder failed checkoutId=${checkoutId}`, err);
    await checkoutRef.update({ status: "cancelled", updatedAt: Timestamp.now() });
    throw new HttpsError("internal", "Failed to create PayPal order");
  }

  // Card orders are completed on our own hosted Card Fields page (there is no
  // PayPal-hosted approval redirect to follow, since we didn't set a
  // payment_source at order-creation time — see paypal.ts).
  let checkoutUrl: string;
  if (paypalSource === "card") {
    checkoutUrl = `${FUNCTIONS_BASE_URL}/payCardCheckout?checkoutId=${checkoutId}`;
  } else {
    const approvalLink = order.links?.find(
      (l) => l.rel === "approve" || l.rel === "payer-action"
    );
    if (!approvalLink?.href) {
      logger.error(
        `[payments] no approval URL checkoutId=${checkoutId} orderId=${order.id} links=${JSON.stringify(order.links)}`
      );
      throw new HttpsError("internal", "PayPal did not return an approval URL");
    }
    logger.info(
      `[payments] approval URL selected rel=${approvalLink.rel} href=${approvalLink.href}`
    );
    checkoutUrl = approvalLink.href;
  }

  await checkoutRef.update({
    paypalOrderId: order.id,
    approvalUrl: checkoutUrl,
    status: "paypal_created",
    updatedAt: Timestamp.now(),
  });

  logger.info(
    `[payments] checkout saved checkoutId=${checkoutId} paypalOrderId=${order.id}`
  );

  return { checkoutUrl };
});

// ─── createPaymentSettingsSession ─────────────────────────────────────────────

export const createPaymentSettingsSession = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const baseUrl = process.env.PUBLIC_BASE_URL ?? FUNCTIONS_BASE_URL;

  logger.info(`[payments] settings session uid=${uid}`);
  return { settingsUrl: `${baseUrl}/billingPage?uid=${uid}` };
});

// ─── createApplePayCheckout / confirmApplePayPayment ──────────────────────────
// Apple Pay is processed through Braintree (see ./braintree.ts), not PayPal —
// the app presents a native PassKit sheet itself, then submits the resulting
// token through these two callables instead of opening a checkout URL.

const APPLE_PAY_MERCHANT_ID = process.env.APPLE_PAY_MERCHANT_ID ?? "";
const APPLE_PAY_COUNTRY_CODE = process.env.APPLE_PAY_COUNTRY_CODE ?? "US";

export const createApplePayCheckout = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const data = req.data as Record<string, unknown>;
  const packageId = (data.pricingOptionId ?? data.packageId) as string | undefined;
  if (!packageId) throw new HttpsError("invalid-argument", "Missing pricing package id");

  logger.info(`[payments] createApplePayCheckout uid=${uid} packageId=${packageId}`);

  const { checkoutId, checkoutRef, pkg } = await resolvePricingAndCreateCheckout({
    uid,
    packageId,
    paymentMethod: "apple_pay",
  });

  let clientToken: string;
  try {
    // Throws BraintreeCurrencyNotSupportedError when no merchant account is
    // declared for this currency — see merchantAccountIdFor.
    clientToken = await generateApplePayClientToken(pkg.currency);
  } catch (err) {
    await checkoutRef.update({ status: "cancelled", updatedAt: Timestamp.now() });
    if (err instanceof BraintreeNotConfiguredError) {
      logger.warn(`[payments] Apple Pay checkout requested but Braintree is not configured checkoutId=${checkoutId}`);
      throw new HttpsError(
        "failed-precondition",
        "Apple Pay is not available yet. Please choose another payment method."
      );
    }
    if (err instanceof BraintreeCurrencyNotSupportedError) {
      logger.warn(
        `[payments] Apple Pay checkout requested in unsupported currency=${pkg.currency} checkoutId=${checkoutId}`
      );
      throw new HttpsError(
        "failed-precondition",
        `Apple Pay does not support ${pkg.currency} yet. Please choose another payment method.`
      );
    }
    logger.error(`[payments] Braintree client token generation failed checkoutId=${checkoutId}`, err);
    throw new HttpsError("internal", "Failed to start Apple Pay checkout");
  }

  logger.info(`[payments] Apple Pay checkout created checkoutId=${checkoutId}`);

  return {
    checkoutId,
    clientToken,
    amountCents: pkg.priceCents,
    currency: pkg.currency,
    merchantIdentifier: APPLE_PAY_MERCHANT_ID,
    countryCode: APPLE_PAY_COUNTRY_CODE,
    label: pkg.name,
  };
});

export const confirmApplePayPayment = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const data = req.data as Record<string, unknown>;
  const checkoutId = data.checkoutId as string | undefined;
  const nonce = data.nonce as string | undefined;
  if (!checkoutId || !nonce) throw new HttpsError("invalid-argument", "Missing checkoutId or nonce");

  const checkoutRef = firestore.collection("paymentCheckouts").doc(checkoutId);
  const checkoutSnap = await checkoutRef.get();
  if (!checkoutSnap.exists) throw new HttpsError("not-found", "Checkout not found");

  const checkout = checkoutSnap.data() as PaymentCheckoutDoc;
  if (checkout.uid !== uid) throw new HttpsError("permission-denied", "Checkout does not belong to this user");
  if (checkout.status === "completed") return { status: "completed" };
  if (checkout.status !== "created")
    throw new HttpsError("failed-precondition", `Checkout is ${checkout.status}`);

  let sale;
  try {
    sale = await createBraintreeSale({
      amountCents: checkout.priceCents,
      currency: checkout.currency,
      nonce,
      orderId: checkoutId,
    });
  } catch (err) {
    logger.error(`[payments] Braintree sale failed checkoutId=${checkoutId}`, err);
    await checkoutRef.update({ status: "cancelled", updatedAt: Timestamp.now() });
    throw new HttpsError("internal", "Apple Pay payment failed");
  }

  if (!sale.success) {
    logger.warn(`[payments] Braintree sale declined checkoutId=${checkoutId} message=${sale.message}`);
    await checkoutRef.update({ status: "cancelled", updatedAt: Timestamp.now() });
    throw new HttpsError("aborted", sale.message ?? "Apple Pay payment was declined");
  }

  await creditCompletedCheckout({
    checkoutRef,
    checkout,
    checkoutId,
    provider: "braintree",
    providerTransactionId: sale.transactionId,
  });

  logger.info(
    `[payments] Apple Pay credited uid=${uid} minutes=${checkout.minutes} checkoutId=${checkoutId}`
  );

  return { status: "completed" };
});

// ─── payCardCheckout (HTTP) ────────────────────────────────────────────────────
// Hosted PayPal Advanced Card Payments (Card Fields) page. The app opens this
// URL in the system browser; on success it redirects to `paypalSuccess`, which
// captures the order and credits minutes exactly like the PayPal-redirect flow.
//
// Requires the PayPal merchant account to be approved for "Advanced Credit and
// Debit Card Payments" — if it isn't, `cardField.isEligible()` in the page's
// script will be false and buyers see a "not available" message instead of
// the card form.

export const payCardCheckout = onRequest(async (req, res) => {
  const checkoutId = req.query.checkoutId as string | undefined;
  if (!checkoutId) {
    res.status(400).send("Missing checkoutId");
    return;
  }

  const checkoutSnap = await firestore.collection("paymentCheckouts").doc(checkoutId).get();
  if (!checkoutSnap.exists) {
    res.status(404).send("Checkout not found");
    return;
  }

  const checkout = checkoutSnap.data() as PaymentCheckoutDoc;
  if (checkout.status === "completed") {
    res.redirect(
      302,
      `teacherminute://payment-return?status=success&order_id=${checkout.paypalOrderId ?? "unknown"}&checkout_id=${checkoutId}`
    );
    return;
  }
  if (!checkout.paypalOrderId) {
    res.status(409).send("Checkout has no order to pay");
    return;
  }

  const clientId = process.env.PAYPAL_CLIENT_ID ?? "";
  const successUrl = `${FUNCTIONS_BASE_URL}/paypalSuccess?checkoutId=${checkoutId}`;
  const cancelUrl = `${FUNCTIONS_BASE_URL}/paypalCancel?checkoutId=${checkoutId}`;
  const amountLabel = `${(checkout.priceCents / 100).toFixed(2)} ${checkout.currency}`;

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Pay by card – TeacherMinute</title>
<style>
body{font-family:system-ui,sans-serif;max-width:420px;margin:2rem auto;padding:0 1rem;color:#111}
h1{font-size:1.2rem}
.amount{color:#555;margin-bottom:1.5rem}
label{display:block;font-size:.8rem;color:#555;margin:.75rem 0 .25rem}
.field{border:1px solid #d1d5db;border-radius:8px;padding:.6rem .75rem;height:2.4rem}
button{margin-top:1.5rem;width:100%;padding:.75rem;border:none;border-radius:8px;background:#2563eb;color:#fff;font-size:1rem;cursor:pointer}
button:disabled{background:#93c5fd;cursor:not-allowed}
.error{color:#b91c1c;font-size:.85rem;margin-top:1rem;display:none}
.cancel{display:block;text-align:center;margin-top:1rem;font-size:.85rem;color:#6b7280}
</style>
</head>
<body>
<h1>Pay by credit or debit card</h1>
<div class="amount">${amountLabel}</div>
<div id="card-form">
  <label>Card number</label><div id="card-number" class="field"></div>
  <label>Expiry</label><div id="card-expiry" class="field"></div>
  <label>CVV</label><div id="card-cvv" class="field"></div>
  <button id="submit-btn" type="button">Pay ${amountLabel}</button>
</div>
<div id="error" class="error"></div>
<a class="cancel" href="${cancelUrl}">Cancel and go back</a>
<script src="https://www.paypal.com/sdk/js?client-id=${encodeURIComponent(clientId)}&currency=${encodeURIComponent(checkout.currency)}&components=card-fields&intent=capture"></script>
<script>
  const orderID = ${JSON.stringify(checkout.paypalOrderId)};
  const submitBtn = document.getElementById("submit-btn");
  const errorEl = document.getElementById("error");
  function showError(message) {
    errorEl.textContent = message;
    errorEl.style.display = "block";
  }
  try {
    const cardField = paypal.CardFields({
      createOrder: () => Promise.resolve(orderID),
      onApprove: () => { window.location.href = ${JSON.stringify(successUrl)}; },
      onError: (err) => {
        console.error(err);
        showError("Card payment failed. Please check your card details and try again.");
        submitBtn.disabled = false;
      },
    });
    if (cardField.isEligible()) {
      cardField.NumberField().render("#card-number");
      cardField.ExpiryField().render("#card-expiry");
      cardField.CVVField().render("#card-cvv");
      submitBtn.addEventListener("click", () => {
        submitBtn.disabled = true;
        cardField.submit().catch((err) => {
          console.error(err);
          showError("Card payment failed. Please check your card details and try again.");
          submitBtn.disabled = false;
        });
      });
    } else {
      document.getElementById("card-form").style.display = "none";
      showError("Card payments are not available right now. Please choose another payment method.");
    }
  } catch (err) {
    console.error(err);
    document.getElementById("card-form").style.display = "none";
    showError("Card payments are not available right now. Please choose another payment method.");
  }
</script>
</body></html>`;

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.status(200).send(html);
});

// ─── paypalSuccess (HTTP) ─────────────────────────────────────────────────────
// PayPal redirects here after buyer approval. Captures the order, credits the
// user, then redirects to the app deep link.

export const paypalSuccess = onRequest(async (req, res) => {
  const checkoutId = req.query.checkoutId as string | undefined;
  const token = req.query.token as string | undefined; // PayPal order id

  logger.info(`[payments] paypalSuccess checkoutId=${checkoutId} token=${token}`);

  const failRedirect = `teacherminute://payment-return?status=cancelled&checkout_id=${checkoutId ?? "unknown"}&order_id=${token ?? "unknown"}`;

  if (!checkoutId) {
    logger.warn(`[payments] paypalSuccess missing checkoutId`);
    res.redirect(302, failRedirect);
    return;
  }

  const checkoutRef = firestore.collection("paymentCheckouts").doc(checkoutId);
  const checkoutSnap = await checkoutRef.get();

  if (!checkoutSnap.exists) {
    logger.error(`[payments] paypalSuccess checkout not found checkoutId=${checkoutId}`);
    res.redirect(302, failRedirect);
    return;
  }

  const checkout = checkoutSnap.data() as PaymentCheckoutDoc;

  if (checkout.status === "completed") {
    logger.info(
      `[payments] paypalSuccess already completed (idempotent) checkoutId=${checkoutId}`
    );
    const deepLink = `teacherminute://payment-return?status=success&order_id=${checkout.paypalOrderId ?? token ?? "unknown"}&checkout_id=${checkoutId}`;
    logger.info(`[payments] paypalSuccess redirect ${deepLink}`);
    res.redirect(302, deepLink);
    return;
  }

  const orderId = token ?? (checkout.paypalOrderId as string | null) ?? "";
  if (!orderId) {
    logger.error(`[payments] paypalSuccess no orderId checkoutId=${checkoutId}`);
    res.redirect(302, failRedirect);
    return;
  }

  let capture;
  try {
    capture = await captureOrder(orderId);
    logger.info(
      `[payments] paypalSuccess capture orderId=${orderId} captureId=${capture.captureId} status=${capture.orderStatus} amountCents=${capture.amountCents} currency=${capture.currency}`
    );
  } catch (err) {
    logger.error(
      `[payments] paypalSuccess captureOrder failed checkoutId=${checkoutId} orderId=${orderId}`,
      err
    );
    // Webhook may have already captured and completed this checkout — check before failing.
    const recheckSnap = await checkoutRef.get();
    if (recheckSnap.data()?.status === "completed") {
      logger.info(
        `[payments] paypalSuccess capture failed but checkout already completed (webhook race) checkoutId=${checkoutId}`
      );
      const deepLink = `teacherminute://payment-return?status=success&order_id=${orderId}&checkout_id=${checkoutId}`;
      logger.info(`[payments] paypalSuccess redirect ${deepLink}`);
      res.redirect(302, deepLink);
      return;
    }
    res.redirect(302, failRedirect);
    return;
  }

  if (capture.orderStatus !== "COMPLETED") {
    logger.error(
      `[payments] paypalSuccess unexpected capture status checkoutId=${checkoutId} status=${capture.orderStatus}`
    );
    res.redirect(302, failRedirect);
    return;
  }

  try {
    await creditCompletedCheckout({
      checkoutRef,
      checkout,
      checkoutId,
      provider: "paypal",
      providerTransactionId: capture.captureId,
      extraCheckoutFields: { paypalOrderId: orderId },
    });
  } catch (err) {
    logger.error(
      `[payments] paypalSuccess transaction failed checkoutId=${checkoutId}`,
      err
    );
    res.redirect(302, failRedirect);
    return;
  }

  logger.info(
    `[payments] paypalSuccess credited uid=${checkout.uid} minutes=${checkout.minutes} checkoutId=${checkoutId}`
  );

  const deepLink = `teacherminute://payment-return?status=success&order_id=${orderId}&checkout_id=${checkoutId}`;
  logger.info(`[payments] paypalSuccess redirect ${deepLink}`);
  res.redirect(302, deepLink);
});

// ─── paypalCancel (HTTP) ──────────────────────────────────────────────────────

export const paypalCancel = onRequest(async (req, res) => {
  const checkoutId = req.query.checkoutId as string | undefined;
  const token = req.query.token as string | undefined;

  logger.info(`[payments] paypalCancel checkoutId=${checkoutId} token=${token}`);

  if (checkoutId) {
    firestore
      .collection("paymentCheckouts")
      .doc(checkoutId)
      .update({ status: "cancelled", updatedAt: Timestamp.now() })
      .catch((err) =>
        logger.warn(`[payments] paypalCancel update failed checkoutId=${checkoutId}`, err)
      );
  }

  const deepLink = `teacherminute://payment-return?status=cancelled&checkout_id=${checkoutId ?? "unknown"}`;
  logger.info(`[payments] paypalCancel redirect ${deepLink}`);
  res.redirect(302, deepLink);
});

// ─── paypalWebhook (HTTP) ─────────────────────────────────────────────────────

export const paypalWebhook = onRequest(async (req, res) => {
  if (req.method !== "POST") {
    res.status(405).send("Method Not Allowed");
    return;
  }

  const webhookId = process.env.PAYPAL_WEBHOOK_ID;
  if (!webhookId) {
    logger.error("[payments] PAYPAL_WEBHOOK_ID not configured");
    res.status(500).send("Webhook not configured");
    return;
  }

  // PayPal sandbox signature verification is unreliable — bypass it in sandbox.
  const isSandbox = process.env.PAYPAL_ENV !== "live";
  if (!isSandbox) {
    const valid = await verifyWebhookSignature({
      transmissionId: (req.headers["paypal-transmission-id"] as string) ?? "",
      transmissionTime: (req.headers["paypal-transmission-time"] as string) ?? "",
      certUrl: (req.headers["paypal-cert-url"] as string) ?? "",
      authAlgo: (req.headers["paypal-auth-algo"] as string) ?? "",
      transmissionSig: (req.headers["paypal-transmission-sig"] as string) ?? "",
      webhookId,
      webhookEvent: req.body as Record<string, unknown>,
    });

    if (!valid) {
      logger.warn("[payments] webhook signature invalid");
      res.status(400).send("Invalid signature");
      return;
    }
  } else {
    logger.info("[payments] webhook signature check skipped (sandbox)");
  }

  const event = req.body as {
    id: string;
    event_type: string;
    resource: Record<string, unknown>;
  };
  const { id: eventId, event_type: eventType, resource } = event;

  const processedRef = firestore.collection("processedWebhooks").doc(eventId);
  if ((await processedRef.get()).exists) {
    logger.info(`[payments] webhook duplicate eventId=${eventId}`);
    res.status(200).send("OK");
    return;
  }

  logger.info(`[payments] webhook received eventId=${eventId} type=${eventType}`);

  try {
    await handleWebhookEvent(eventType, resource);
  } catch (err) {
    logger.error(
      `[payments] webhook handler failed eventId=${eventId} type=${eventType}`,
      err
    );
    res.status(500).send("Handler error");
    return;
  }

  await processedRef.set({ eventId, eventType, processedAt: Timestamp.now() });
  res.status(200).send("OK");
});

async function handleWebhookEvent(
  eventType: string,
  resource: Record<string, unknown>
): Promise<void> {
  switch (eventType) {
    case "CHECKOUT.ORDER.APPROVED":
      logger.info(`[payments] webhook order approved orderId=${resource["id"]}`);
      break;

    case "PAYMENT.CAPTURE.COMPLETED": {
      const captureId = resource["id"] as string;
      const invoiceId = resource["invoice_id"] as string | undefined; // == checkoutId
      const captureAmount = resource["amount"] as
        | { value: string; currency_code: string }
        | undefined;

      if (!invoiceId || !captureAmount) {
        logger.warn(
          `[payments] webhook CAPTURE.COMPLETED missing fields captureId=${captureId}`
        );
        break;
      }

      const checkoutRef = firestore.collection("paymentCheckouts").doc(invoiceId);
      const checkoutSnap = await checkoutRef.get();
      if (!checkoutSnap.exists) {
        logger.warn(
          `[payments] webhook CAPTURE.COMPLETED checkout not found checkoutId=${invoiceId}`
        );
        break;
      }

      const checkout = checkoutSnap.data() as PaymentCheckoutDoc;
      if (checkout.status === "completed") {
        logger.info(
          `[payments] webhook CAPTURE.COMPLETED already completed checkoutId=${invoiceId}`
        );
        break;
      }

      const amountCents = Math.round(parseFloat(captureAmount.value) * 100);
      if (
        amountCents !== checkout.priceCents ||
        captureAmount.currency_code !== checkout.currency
      ) {
        logger.error(
          `[payments] webhook CAPTURE.COMPLETED amount mismatch checkoutId=${invoiceId} got=${amountCents}/${captureAmount.currency_code} expected=${checkout.priceCents}/${checkout.currency}`
        );
        break;
      }

      await creditCompletedCheckout({
        checkoutRef,
        checkout,
        checkoutId: invoiceId,
        provider: "paypal",
        providerTransactionId: captureId,
      });

      logger.info(
        `[payments] webhook reconciled checkoutId=${invoiceId} captureId=${captureId} uid=${checkout.uid} minutes=${checkout.minutes}`
      );
      break;
    }

    case "PAYMENT.CAPTURE.DENIED": {
      const captureId = resource["id"] as string;
      const invoiceId = resource["invoice_id"] as string | undefined;
      if (!invoiceId) {
        logger.warn(
          `[payments] webhook CAPTURE.DENIED missing invoiceId captureId=${captureId}`
        );
        break;
      }
      await firestore
        .collection("paymentCheckouts")
        .doc(invoiceId)
        .update({ status: "cancelled", updatedAt: Timestamp.now() })
        .catch((err) =>
          logger.warn(
            `[payments] webhook CAPTURE.DENIED update failed checkoutId=${invoiceId}`,
            err
          )
        );
      logger.info(
        `[payments] webhook capture denied checkoutId=${invoiceId} captureId=${captureId}`
      );
      break;
    }

    case "PAYMENT.CAPTURE.REFUNDED":
      logger.info(`[payments] webhook refund received captureId=${resource["id"]}`);
      break;

    default:
      logger.info(`[payments] webhook unhandled type=${eventType}`);
  }
}

// ─── billingPage (HTTP) ───────────────────────────────────────────────────────

export const billingPage = onRequest(async (req, res) => {
  const uid = req.query.uid as string | undefined;
  if (!uid) {
    res.status(400).send("Missing uid");
    return;
  }

  const checkoutsSnap = await firestore
    .collection("paymentCheckouts")
    .where("uid", "==", uid)
    .orderBy("createdAt", "desc")
    .limit(20)
    .get();

  const fmt = (ts: Timestamp | undefined) =>
    ts ? new Date(ts.toMillis()).toLocaleDateString("en-US") : "—";

  const money = (cents: number, currency: string) =>
    `${(cents / 100).toFixed(2)} ${currency}`;

  const esc = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  const rows =
    checkoutsSnap.docs
      .map((doc) => {
        const d = doc.data() as PaymentCheckoutDoc;
        return `<tr><td>${esc(doc.id.slice(0, 8))}…</td><td>${fmt(d.createdAt)}</td><td>${money(d.priceCents, d.currency)}</td><td>${d.minutes} min</td><td>${esc(d.status)}</td></tr>`;
      })
      .join("") || "<tr><td colspan='5'>No payments yet.</td></tr>";

  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Billing – TeacherMinute</title>
<style>
body{font-family:system-ui,sans-serif;max-width:800px;margin:2rem auto;padding:0 1rem}
h1{font-size:1.4rem}h2{font-size:1rem;margin-top:2rem;color:#555}
table{width:100%;border-collapse:collapse;font-size:.875rem}
th,td{text-align:left;padding:.5rem .75rem;border-bottom:1px solid #e5e7eb}
th{background:#f9fafb;font-weight:600}
.support{margin-top:2rem;font-size:.875rem;color:#6b7280}a{color:#2563eb}
</style>
</head>
<body>
<h1>Billing History</h1>
<table>
<thead><tr><th>ID</th><th>Date</th><th>Amount</th><th>Minutes</th><th>Status</th></tr></thead>
<tbody>${rows}</tbody>
</table>
<div class="support">Need help? <a href="mailto:support@teacherminute.com">Contact support</a></div>
</body></html>`;

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.status(200).send(html);
});
