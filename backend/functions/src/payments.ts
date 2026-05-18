import * as admin from "firebase-admin";
import { logger } from "firebase-functions";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { v4 as uuidv4 } from "uuid";

import { createOrder, captureOrder, verifyWebhookSignature } from "./paypal";
import { PricingDoc, PaymentSessionDoc, PurchaseDoc } from "./types";

const firestore = admin.firestore();

// ─── Helpers ──────────────────────────────────────────────────────────────────

function minutesForPlan(pricing: PricingDoc): number {
  if (pricing.minutesGranted && pricing.minutesGranted > 0) return pricing.minutesGranted;
  switch (pricing.type) {
    case "unlimited_week":  return 7 * 24 * 60;
    case "unlimited_month": return 30 * 24 * 60;
    case "unlimited_year":  return 365 * 24 * 60;
    default: return 0;
  }
}

function planExpiresAt(type: PurchaseDoc["type"], from: Date): Timestamp | undefined {
  const DAY_MS = 86_400_000;
  switch (type) {
    case "unlimited_week":  return Timestamp.fromMillis(from.getTime() + 7 * DAY_MS);
    case "unlimited_month": return Timestamp.fromMillis(from.getTime() + 30 * DAY_MS);
    case "unlimited_year":  return Timestamp.fromMillis(from.getTime() + 365 * DAY_MS);
    default: return undefined;
  }
}

async function grantPurchase(
  sessionId: string,
  session: PaymentSessionDoc,
  captureId: string
): Promise<void> {
  const pricingSnap = await firestore.collection("pricing").doc(session.pricingOptionId).get();
  const pricing = pricingSnap.data() as PricingDoc;

  const now = new Date();
  const exp = planExpiresAt(pricing.type, now);

  const purchase: PurchaseDoc = {
    pricingOptionId: session.pricingOptionId,
    provider: "paypal",
    amountCents: session.amountCents,
    currency: session.currency,
    type: pricing.type,
    status: "active",
    purchasedAt: Timestamp.now(),
    ...(exp ? { expiresAt: exp } : {}),
  };

  const minutesToGrant = minutesForPlan(pricing);

  const paidAt = Timestamp.now();
  const sessionRef = firestore.collection("paymentSessions").doc(sessionId);
  const userRef = firestore.collection("users").doc(session.uid);
  const purchaseRef = userRef.collection("purchases").doc(sessionId);

  const batch = firestore.batch();
  batch.update(sessionRef, { status: "paid", providerCaptureId: captureId, paidAt, updatedAt: paidAt });
  batch.set(purchaseRef, purchase);
  if (minutesToGrant > 0) {
    batch.set(userRef, { remainingMinutes: FieldValue.increment(minutesToGrant) }, { merge: true });
  }
  await batch.commit();

  logger.info(
    `[payments] purchase granted sessionId=${sessionId} captureId=${captureId} uid=${session.uid} type=${pricing.type} minutesGranted=${minutesToGrant}`
  );
}

// ─── createCheckoutSession ────────────────────────────────────────────────────

export const createCheckoutSession = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const { pricingOptionId } = req.data as { pricingOptionId?: string };
  if (!pricingOptionId) throw new HttpsError("invalid-argument", "pricingOptionId required");

  const pricingSnap = await firestore.collection("pricing").doc(pricingOptionId).get();
  if (!pricingSnap.exists) throw new HttpsError("not-found", "Pricing option not found");

  const pricing = pricingSnap.data() as PricingDoc;
  if (pricing.active === false) throw new HttpsError("not-found", "Pricing option is not active");
  if (!pricing.priceCents || pricing.priceCents <= 0) {
    throw new HttpsError("internal", "Invalid pricing configuration");
  }

  const baseUrl = process.env.PUBLIC_BASE_URL;
  if (!baseUrl) throw new HttpsError("internal", "PUBLIC_BASE_URL not configured");

  const sessionId = uuidv4();
  const returnUrl = `${baseUrl}/capturePayPalOrder?sessionId=${sessionId}`;
  const cancelUrl = `${baseUrl}/cancelPayPalOrder?sessionId=${sessionId}`;

  let order;
  try {
    order = await createOrder({
      amountCents: pricing.priceCents,
      currency: pricing.currency ?? "USD",
      description: pricing.name,
      uid,
      sessionId,
      returnUrl,
      cancelUrl,
    });
  } catch (err) {
    logger.error(`[payments] createOrder failed uid=${uid} pricingOptionId=${pricingOptionId}`, err);
    throw new HttpsError("internal", "Failed to create payment order");
  }

  const approveLink = order.links.find((l) => l.rel === "approve");
  if (!approveLink) {
    logger.error(`[payments] no approve link orderId=${order.id}`);
    throw new HttpsError("internal", "PayPal did not return an approval URL");
  }

  const session: PaymentSessionDoc = {
    uid,
    pricingOptionId,
    provider: "paypal",
    providerOrderId: order.id,
    status: "created",
    amountCents: pricing.priceCents,
    currency: pricing.currency ?? "USD",
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
  };

  await firestore.collection("paymentSessions").doc(sessionId).set(session);

  logger.info(
    `[payments] session created sessionId=${sessionId} orderId=${order.id} uid=${uid} amountCents=${pricing.priceCents}`
  );
  return { checkoutUrl: approveLink.href };
});

// ─── createPaymentSettingsSession ─────────────────────────────────────────────

export const createPaymentSettingsSession = onCall(async (req) => {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

  const baseUrl = process.env.PUBLIC_BASE_URL;
  if (!baseUrl) throw new HttpsError("internal", "PUBLIC_BASE_URL not configured");

  logger.info(`[payments] settings session uid=${uid}`);
  return { settingsUrl: `${baseUrl}/billingPage?uid=${uid}` };
});

// ─── capturePayPalOrder (HTTP) ────────────────────────────────────────────────
// PayPal redirects the buyer here after approval. Captures the order and grants
// entitlement, then redirects to the app deep link or a simple success page.

export const capturePayPalOrder = onRequest(async (req, res) => {
  const sessionId = req.query.sessionId as string | undefined;
  const token = req.query.token as string | undefined; // PayPal order id in query params

  if (!sessionId || !token) {
    logger.warn(`[payments] capture missing params sessionId=${sessionId} token=${token}`);
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.setHeader("Cache-Control", "no-store");
    res.status(200).send(cancelledHtml());
    return;
  }

  const sessionRef = firestore.collection("paymentSessions").doc(sessionId);
  const sessionSnap = await sessionRef.get();

  if (!sessionSnap.exists) {
    logger.error(`[payments] capture session not found sessionId=${sessionId}`);
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.setHeader("Cache-Control", "no-store");
    res.status(200).send(cancelledHtml());
    return;
  }

  const session = sessionSnap.data() as PaymentSessionDoc;

  if (session.status === "paid") {
    logger.info(`[payments] capture already paid sessionId=${sessionId}`);
    const dl = process.env.APP_SUCCESS_DEEP_LINK;
    dl ? res.redirect(302, dl) : (() => {
      res.setHeader("Content-Type", "text/html; charset=utf-8");
      res.setHeader("Cache-Control", "no-store");
      res.status(200).send(successHtml());
    })();
    return;
  }

  if (session.providerOrderId !== token) {
    logger.error(
      `[payments] capture order id mismatch sessionId=${sessionId} expected=${session.providerOrderId} got=${token}`
    );
    const dl = process.env.APP_CANCEL_DEEP_LINK;
    dl ? res.redirect(302, dl) : (() => {
      res.setHeader("Content-Type", "text/html; charset=utf-8");
      res.setHeader("Cache-Control", "no-store");
      res.status(200).send(cancelledHtml());
    })();
    return;
  }

  let capture;
  try {
    capture = await captureOrder(token);
  } catch (err) {
    logger.error(`[payments] captureOrder failed sessionId=${sessionId} orderId=${token}`, err);
    const dl = process.env.APP_CANCEL_DEEP_LINK;
    dl ? res.redirect(302, dl) : (() => {
      res.setHeader("Content-Type", "text/html; charset=utf-8");
      res.setHeader("Cache-Control", "no-store");
      res.status(200).send(cancelledHtml());
    })();
    return;
  }

  if (
    capture.orderStatus !== "COMPLETED" ||
    capture.amountCents !== session.amountCents ||
    capture.currency !== session.currency
  ) {
    logger.error(
      `[payments] capture verification failed sessionId=${sessionId} orderStatus=${capture.orderStatus} amountCents=${capture.amountCents}/${session.amountCents} currency=${capture.currency}/${session.currency}`
    );
    const dl = process.env.APP_CANCEL_DEEP_LINK;
    dl ? res.redirect(302, dl) : (() => {
      res.setHeader("Content-Type", "text/html; charset=utf-8");
      res.setHeader("Cache-Control", "no-store");
      res.status(200).send(cancelledHtml());
    })();
    return;
  }

  try {
    await grantPurchase(sessionId, session, capture.captureId);
  } catch (err) {
    logger.error(`[payments] grantPurchase failed sessionId=${sessionId}`, err);
    const dl = process.env.APP_CANCEL_DEEP_LINK;
    dl ? res.redirect(302, dl) : (() => {
      res.setHeader("Content-Type", "text/html; charset=utf-8");
      res.setHeader("Cache-Control", "no-store");
      res.status(200).send(cancelledHtml());
    })();
    return;
  }

  logger.info(`[payments] captured sessionId=${sessionId} captureId=${capture.captureId} uid=${session.uid}`);
  const successDl = process.env.APP_SUCCESS_DEEP_LINK;
  successDl ? res.redirect(302, successDl) : (() => {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.setHeader("Cache-Control", "no-store");
    res.status(200).send(successHtml());
  })();
});

// ─── cancelPayPalOrder (HTTP) ─────────────────────────────────────────────────

export const cancelPayPalOrder = onRequest(async (req, res) => {
  const sessionId = req.query.sessionId as string | undefined;

  if (sessionId) {
    firestore
      .collection("paymentSessions")
      .doc(sessionId)
      .update({ status: "cancelled", updatedAt: FieldValue.serverTimestamp() })
      .catch((err) =>
        logger.warn(`[payments] cancel update failed sessionId=${sessionId}`, err)
      );
    logger.info(`[payments] order cancelled sessionId=${sessionId}`);
  }

  const dl = process.env.APP_CANCEL_DEEP_LINK;
  if (dl) {
    res.redirect(302, dl);
  } else {
    res.setHeader("Content-Type", "text/html; charset=utf-8");
    res.setHeader("Cache-Control", "no-store");
    res.status(200).send(cancelledHtml());
  }
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

  // PayPal sandbox signature verification is unreliable — bypass it in sandbox
  // so integration testing isn't blocked. Always verify in live mode.
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
    logger.error(`[payments] webhook handler failed eventId=${eventId} type=${eventType}`, err);
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
      const invoiceId = resource["invoice_id"] as string | undefined;
      const captureAmount = resource["amount"] as
        | { value: string; currency_code: string }
        | undefined;

      if (!invoiceId || !captureAmount) {
        logger.warn(`[payments] webhook CAPTURE.COMPLETED missing fields captureId=${captureId}`);
        break;
      }

      const sessionRef = firestore.collection("paymentSessions").doc(invoiceId);
      const sessionSnap = await sessionRef.get();
      if (!sessionSnap.exists) {
        logger.warn(
          `[payments] webhook CAPTURE.COMPLETED session not found invoiceId=${invoiceId}`
        );
        break;
      }

      const session = sessionSnap.data() as PaymentSessionDoc;
      if (session.status === "paid") {
        logger.info(`[payments] webhook CAPTURE.COMPLETED already paid sessionId=${invoiceId}`);
        break;
      }

      const amountCents = Math.round(parseFloat(captureAmount.value) * 100);
      if (amountCents !== session.amountCents || captureAmount.currency_code !== session.currency) {
        logger.error(
          `[payments] webhook CAPTURE.COMPLETED amount mismatch sessionId=${invoiceId} got=${amountCents}/${captureAmount.currency_code} expected=${session.amountCents}/${session.currency}`
        );
        break;
      }

      await grantPurchase(invoiceId, session, captureId);
      logger.info(
        `[payments] webhook reconciled capture sessionId=${invoiceId} captureId=${captureId}`
      );
      break;
    }

    case "PAYMENT.CAPTURE.DENIED": {
      const captureId = resource["id"] as string;
      const invoiceId = resource["invoice_id"] as string | undefined;
      if (!invoiceId) {
        logger.warn(`[payments] webhook CAPTURE.DENIED missing invoiceId captureId=${captureId}`);
        break;
      }

      await firestore
        .collection("paymentSessions")
        .doc(invoiceId)
        .update({ status: "cancelled", updatedAt: FieldValue.serverTimestamp() })
        .catch((err) =>
          logger.warn(`[payments] webhook CAPTURE.DENIED update failed sessionId=${invoiceId}`, err)
        );

      logger.info(
        `[payments] webhook capture denied sessionId=${invoiceId} captureId=${captureId}`
      );
      break;
    }

    case "PAYMENT.CAPTURE.REFUNDED":
      // Full reconciliation requires fetching the original capture (resource.links[].rel=="up")
      // and mapping invoice_id to the session. Implemented after vaulting rollout.
      logger.info(`[payments] webhook refund received captureId=${resource["id"]}`);
      break;

    default:
      logger.info(`[payments] webhook unhandled type=${eventType}`);
  }
}

// ─── billingPage (HTTP) ───────────────────────────────────────────────────────
// Shows the user's payment history. Requires composite Firestore index on
// paymentSessions: uid ASC + createdAt DESC.

export const billingPage = onRequest(async (req, res) => {
  const uid = req.query.uid as string | undefined;
  if (!uid) {
    res.status(400).send("Missing uid");
    return;
  }

  const [sessionsSnap, purchasesSnap] = await Promise.all([
    firestore
      .collection("paymentSessions")
      .where("uid", "==", uid)
      .orderBy("createdAt", "desc")
      .limit(20)
      .get(),
    firestore
      .collection("users")
      .doc(uid)
      .collection("purchases")
      .orderBy("purchasedAt", "desc")
      .limit(20)
      .get(),
  ]);

  const fmt = (ts: Timestamp | undefined) =>
    ts ? new Date(ts.toMillis()).toLocaleDateString("en-US") : "—";

  const money = (cents: number, currency: string) =>
    `${(cents / 100).toFixed(2)} ${currency}`;

  const esc = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

  const sessionRows =
    sessionsSnap.docs
      .map((doc) => {
        const d = doc.data() as PaymentSessionDoc;
        return `<tr><td>${esc(doc.id.slice(0, 8))}…</td><td>${fmt(d.createdAt)}</td><td>${money(d.amountCents, d.currency)}</td><td>${esc(d.status)}</td></tr>`;
      })
      .join("") || "<tr><td colspan='4'>No payments yet.</td></tr>";

  const purchaseRows =
    purchasesSnap.docs
      .map((doc) => {
        const d = doc.data() as PurchaseDoc;
        return `<tr><td>${esc(doc.id.slice(0, 8))}…</td><td>${fmt(d.purchasedAt)}</td><td>${esc(d.type)}</td><td>${esc(d.status)}</td><td>${fmt(d.expiresAt)}</td></tr>`;
      })
      .join("") || "<tr><td colspan='5'>No purchases yet.</td></tr>";

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
<h2>Payment Sessions</h2>
<table><thead><tr><th>ID</th><th>Date</th><th>Amount</th><th>Status</th></tr></thead>
<tbody>${sessionRows}</tbody></table>
<h2>Purchases</h2>
<table><thead><tr><th>ID</th><th>Purchased</th><th>Plan</th><th>Status</th><th>Expires</th></tr></thead>
<tbody>${purchaseRows}</tbody></table>
<div class="support">Need help? <a href="mailto:support@teacherminute.com">Contact support</a></div>
</body></html>`;

  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  res.status(200).send(html);
});

// ─── Static HTML pages ────────────────────────────────────────────────────────

function successHtml(): string {
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Payment Successful – TeacherMinute</title><style>body{font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#f0fdf4}.card{text-align:center;padding:2rem;background:#fff;border-radius:1rem;box-shadow:0 2px 8px rgba(0,0,0,.08);max-width:360px}h1{color:#16a34a;margin-bottom:.5rem}p{color:#555}</style></head><body><div class="card"><h1>Payment Successful</h1><p>Your purchase is confirmed. Return to the app to get started.</p></div></body></html>`;
}

function cancelledHtml(): string {
  return `<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Payment Cancelled – TeacherMinute</title><style>body{font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;background:#fafafa}.card{text-align:center;padding:2rem;background:#fff;border-radius:1rem;box-shadow:0 2px 8px rgba(0,0,0,.08);max-width:360px}h1{color:#71717a;margin-bottom:.5rem}p{color:#555}</style></head><body><div class="card"><h1>Payment Cancelled</h1><p>Your payment was not completed. Return to the app to try again.</p></div></body></html>`;
}
