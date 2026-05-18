"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.billingPage = exports.paypalWebhook = exports.paypalCancel = exports.paypalSuccess = exports.createPaymentSettingsSession = exports.createCheckoutSession = void 0;
const admin = require("firebase-admin");
const firebase_functions_1 = require("firebase-functions");
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const uuid_1 = require("uuid");
const paypal_1 = require("./paypal");
const firestore = admin.firestore();
// ─── Helpers ──────────────────────────────────────────────────────────────────
function minutesForPlan(pricing) {
    if (pricing.minutesGranted && pricing.minutesGranted > 0)
        return pricing.minutesGranted;
    if (pricing.minutes && pricing.minutes > 0)
        return pricing.minutes;
    switch (pricing.type) {
        case "unlimited_week": return 7 * 24 * 60;
        case "unlimited_month": return 30 * 24 * 60;
        case "unlimited_year": return 365 * 24 * 60;
        default: return 0;
    }
}
function planExpiresAt(type, from) {
    const DAY_MS = 86400000;
    switch (type) {
        case "unlimited_week": return firestore_1.Timestamp.fromMillis(from.getTime() + 7 * DAY_MS);
        case "unlimited_month": return firestore_1.Timestamp.fromMillis(from.getTime() + 30 * DAY_MS);
        case "unlimited_year": return firestore_1.Timestamp.fromMillis(from.getTime() + 365 * DAY_MS);
        default: return undefined;
    }
}
async function grantPurchase(sessionId, session, captureId) {
    const pricingSnap = await firestore.collection("pricing").doc(session.pricingOptionId).get();
    const pricing = pricingSnap.data();
    const now = new Date();
    const exp = planExpiresAt(pricing.type, now);
    const purchase = Object.assign({ pricingOptionId: session.pricingOptionId, provider: "paypal", amountCents: session.amountCents, currency: session.currency, type: pricing.type, status: "active", purchasedAt: firestore_1.Timestamp.now() }, (exp ? { expiresAt: exp } : {}));
    const minutesToGrant = minutesForPlan(pricing);
    const sessionRef = firestore.collection("paymentSessions").doc(sessionId);
    const userRef = firestore.collection("users").doc(session.uid);
    const purchaseRef = userRef.collection("purchases").doc(sessionId);
    await firestore.runTransaction(async (tx) => {
        var _a;
        const freshSnap = await tx.get(sessionRef);
        if (((_a = freshSnap.data()) === null || _a === void 0 ? void 0 : _a.status) === "paid") {
            firebase_functions_1.logger.info(`[payments] grantPurchase already paid (idempotent) sessionId=${sessionId}`);
            return;
        }
        const paidAt = firestore_1.Timestamp.now();
        tx.update(sessionRef, { status: "paid", providerCaptureId: captureId, paidAt, updatedAt: paidAt });
        tx.set(purchaseRef, purchase);
        if (minutesToGrant > 0) {
            tx.set(userRef, { remainingMinutes: firestore_1.FieldValue.increment(minutesToGrant) }, { merge: true });
        }
    });
    firebase_functions_1.logger.info(`[payments] purchase granted sessionId=${sessionId} captureId=${captureId} uid=${session.uid} package=${session.pricingOptionId} type=${pricing.type} minutesGranted=${minutesToGrant}`);
}
// ─── createCheckoutSession ────────────────────────────────────────────────────
exports.createCheckoutSession = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d, _e, _f;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const data = req.data;
    const pricingOptionId = ((_d = (_c = (_b = data.pricingOptionId) !== null && _b !== void 0 ? _b : data.pricingOptionID) !== null && _c !== void 0 ? _c : data.packageId) !== null && _d !== void 0 ? _d : data.packageID);
    firebase_functions_1.logger.info(`[payments] createCheckoutSession uid=${uid} packageId=${pricingOptionId !== null && pricingOptionId !== void 0 ? pricingOptionId : "(missing)"}`);
    if (!pricingOptionId)
        throw new https_1.HttpsError("invalid-argument", "pricingOptionId required");
    const pricingSnap = await firestore.collection("pricing").doc(pricingOptionId).get();
    if (!pricingSnap.exists)
        throw new https_1.HttpsError("not-found", "Pricing option not found");
    const pricing = pricingSnap.data();
    if (pricing.active === false)
        throw new https_1.HttpsError("not-found", "Pricing option is not active");
    if (!pricing.priceCents || pricing.priceCents <= 0) {
        throw new https_1.HttpsError("internal", "Invalid pricing configuration");
    }
    const baseUrl = process.env.PUBLIC_BASE_URL;
    if (!baseUrl)
        throw new https_1.HttpsError("internal", "PUBLIC_BASE_URL not configured");
    const sessionId = (0, uuid_1.v4)();
    const returnUrl = `${baseUrl}/paypalSuccess?sessionId=${sessionId}`;
    const cancelUrl = `${baseUrl}/paypalCancel?sessionId=${sessionId}`;
    let order;
    try {
        order = await (0, paypal_1.createOrder)({
            amountCents: pricing.priceCents,
            currency: (_e = pricing.currency) !== null && _e !== void 0 ? _e : "USD",
            description: pricing.name,
            uid,
            sessionId,
            returnUrl,
            cancelUrl,
        });
    }
    catch (err) {
        firebase_functions_1.logger.error(`[payments] createOrder failed uid=${uid} pricingOptionId=${pricingOptionId}`, err);
        throw new https_1.HttpsError("internal", "Failed to create payment order");
    }
    const approveLink = order.links.find((l) => l.rel === "approve" || l.rel === "payer-action");
    if (!approveLink) {
        firebase_functions_1.logger.error(`[payments] no approve link orderId=${order.id} links=${JSON.stringify(order.links)}`);
        throw new https_1.HttpsError("internal", "PayPal did not return an approval URL");
    }
    firebase_functions_1.logger.info(`[payments] approval URL rel=${approveLink.rel} href=${approveLink.href} orderId=${order.id}`);
    const session = {
        uid,
        pricingOptionId,
        provider: "paypal",
        providerOrderId: order.id,
        status: "created",
        amountCents: pricing.priceCents,
        currency: (_f = pricing.currency) !== null && _f !== void 0 ? _f : "USD",
        createdAt: firestore_1.Timestamp.now(),
        updatedAt: firestore_1.Timestamp.now(),
    };
    await firestore.collection("paymentSessions").doc(sessionId).set(session);
    firebase_functions_1.logger.info(`[payments] session created sessionId=${sessionId} orderId=${order.id} uid=${uid} amountCents=${pricing.priceCents}`);
    return { checkoutUrl: approveLink.href };
});
// ─── createPaymentSettingsSession ─────────────────────────────────────────────
exports.createPaymentSettingsSession = (0, https_1.onCall)(async (req) => {
    var _a;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const baseUrl = process.env.PUBLIC_BASE_URL;
    if (!baseUrl)
        throw new https_1.HttpsError("internal", "PUBLIC_BASE_URL not configured");
    firebase_functions_1.logger.info(`[payments] settings session uid=${uid}`);
    return { settingsUrl: `${baseUrl}/billingPage?uid=${uid}` };
});
// ─── paypalSuccess (HTTP) ─────────────────────────────────────────────────────
// PayPal redirects the buyer here after approval. Captures the order and grants
// entitlement, then redirects to the app deep link or a simple success page.
exports.paypalSuccess = (0, https_1.onRequest)(async (req, res) => {
    const sessionId = req.query.sessionId;
    const token = req.query.token; // PayPal order id
    firebase_functions_1.logger.info(`[payments] paypalSuccess sessionId=${sessionId} token=${token}`);
    const failRedirect = `teacherminute://payment-return?status=cancelled&order_id=${token !== null && token !== void 0 ? token : "unknown"}`;
    if (!sessionId || !token) {
        firebase_functions_1.logger.warn(`[payments] paypalSuccess missing params — redirecting cancelled`);
        res.redirect(302, failRedirect);
        return;
    }
    const sessionRef = firestore.collection("paymentSessions").doc(sessionId);
    const sessionSnap = await sessionRef.get();
    if (!sessionSnap.exists) {
        firebase_functions_1.logger.error(`[payments] paypalSuccess session not found sessionId=${sessionId}`);
        res.redirect(302, failRedirect);
        return;
    }
    const session = sessionSnap.data();
    if (session.status === "paid") {
        firebase_functions_1.logger.info(`[payments] paypalSuccess already paid (idempotent) sessionId=${sessionId}`);
        const deepLink = `teacherminute://payment-return?status=success&order_id=${token}`;
        firebase_functions_1.logger.info(`[payments] paypalSuccess redirect ${deepLink}`);
        res.redirect(302, deepLink);
        return;
    }
    if (session.providerOrderId !== token) {
        firebase_functions_1.logger.error(`[payments] paypalSuccess order id mismatch sessionId=${sessionId} expected=${session.providerOrderId} got=${token}`);
        res.redirect(302, failRedirect);
        return;
    }
    let capture;
    try {
        capture = await (0, paypal_1.captureOrder)(token);
        firebase_functions_1.logger.info(`[payments] paypalSuccess capture orderId=${token} captureId=${capture.captureId} status=${capture.orderStatus} amountCents=${capture.amountCents} currency=${capture.currency}`);
    }
    catch (err) {
        firebase_functions_1.logger.error(`[payments] paypalSuccess captureOrder failed sessionId=${sessionId} orderId=${token}`, err);
        res.redirect(302, failRedirect);
        return;
    }
    if (capture.orderStatus !== "COMPLETED" ||
        capture.amountCents !== session.amountCents ||
        capture.currency !== session.currency) {
        firebase_functions_1.logger.error(`[payments] paypalSuccess capture verification failed sessionId=${sessionId} orderStatus=${capture.orderStatus} amountCents=${capture.amountCents}/${session.amountCents} currency=${capture.currency}/${session.currency}`);
        res.redirect(302, failRedirect);
        return;
    }
    try {
        await grantPurchase(sessionId, session, capture.captureId);
    }
    catch (err) {
        firebase_functions_1.logger.error(`[payments] paypalSuccess grantPurchase failed sessionId=${sessionId}`, err);
        res.redirect(302, failRedirect);
        return;
    }
    const deepLink = `teacherminute://payment-return?status=success&order_id=${token}`;
    firebase_functions_1.logger.info(`[payments] paypalSuccess complete sessionId=${sessionId} captureId=${capture.captureId} uid=${session.uid} redirect=${deepLink}`);
    res.redirect(302, deepLink);
});
// ─── paypalCancel (HTTP) ──────────────────────────────────────────────────────
exports.paypalCancel = (0, https_1.onRequest)(async (req, res) => {
    const sessionId = req.query.sessionId;
    const token = req.query.token; // PayPal order id
    firebase_functions_1.logger.info(`[payments] paypalCancel sessionId=${sessionId} token=${token}`);
    if (sessionId) {
        firestore
            .collection("paymentSessions")
            .doc(sessionId)
            .update({ status: "cancelled", updatedAt: firestore_1.FieldValue.serverTimestamp() })
            .catch((err) => firebase_functions_1.logger.warn(`[payments] paypalCancel update failed sessionId=${sessionId}`, err));
    }
    const orderId = token !== null && token !== void 0 ? token : "unknown";
    const deepLink = `teacherminute://payment-return?status=cancelled&order_id=${orderId}`;
    firebase_functions_1.logger.info(`[payments] paypalCancel redirect ${deepLink}`);
    res.redirect(302, deepLink);
});
// ─── paypalWebhook (HTTP) ─────────────────────────────────────────────────────
exports.paypalWebhook = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b, _c, _d, _e;
    if (req.method !== "POST") {
        res.status(405).send("Method Not Allowed");
        return;
    }
    const webhookId = process.env.PAYPAL_WEBHOOK_ID;
    if (!webhookId) {
        firebase_functions_1.logger.error("[payments] PAYPAL_WEBHOOK_ID not configured");
        res.status(500).send("Webhook not configured");
        return;
    }
    // PayPal sandbox signature verification is unreliable — bypass it in sandbox
    // so integration testing isn't blocked. Always verify in live mode.
    const isSandbox = process.env.PAYPAL_ENV !== "live";
    if (!isSandbox) {
        const valid = await (0, paypal_1.verifyWebhookSignature)({
            transmissionId: (_a = req.headers["paypal-transmission-id"]) !== null && _a !== void 0 ? _a : "",
            transmissionTime: (_b = req.headers["paypal-transmission-time"]) !== null && _b !== void 0 ? _b : "",
            certUrl: (_c = req.headers["paypal-cert-url"]) !== null && _c !== void 0 ? _c : "",
            authAlgo: (_d = req.headers["paypal-auth-algo"]) !== null && _d !== void 0 ? _d : "",
            transmissionSig: (_e = req.headers["paypal-transmission-sig"]) !== null && _e !== void 0 ? _e : "",
            webhookId,
            webhookEvent: req.body,
        });
        if (!valid) {
            firebase_functions_1.logger.warn("[payments] webhook signature invalid");
            res.status(400).send("Invalid signature");
            return;
        }
    }
    else {
        firebase_functions_1.logger.info("[payments] webhook signature check skipped (sandbox)");
    }
    const event = req.body;
    const { id: eventId, event_type: eventType, resource } = event;
    const processedRef = firestore.collection("processedWebhooks").doc(eventId);
    if ((await processedRef.get()).exists) {
        firebase_functions_1.logger.info(`[payments] webhook duplicate eventId=${eventId}`);
        res.status(200).send("OK");
        return;
    }
    firebase_functions_1.logger.info(`[payments] webhook received eventId=${eventId} type=${eventType}`);
    try {
        await handleWebhookEvent(eventType, resource);
    }
    catch (err) {
        firebase_functions_1.logger.error(`[payments] webhook handler failed eventId=${eventId} type=${eventType}`, err);
        res.status(500).send("Handler error");
        return;
    }
    await processedRef.set({ eventId, eventType, processedAt: firestore_1.Timestamp.now() });
    res.status(200).send("OK");
});
async function handleWebhookEvent(eventType, resource) {
    switch (eventType) {
        case "CHECKOUT.ORDER.APPROVED":
            firebase_functions_1.logger.info(`[payments] webhook order approved orderId=${resource["id"]}`);
            break;
        case "PAYMENT.CAPTURE.COMPLETED": {
            const captureId = resource["id"];
            const invoiceId = resource["invoice_id"];
            const captureAmount = resource["amount"];
            if (!invoiceId || !captureAmount) {
                firebase_functions_1.logger.warn(`[payments] webhook CAPTURE.COMPLETED missing fields captureId=${captureId}`);
                break;
            }
            const sessionRef = firestore.collection("paymentSessions").doc(invoiceId);
            const sessionSnap = await sessionRef.get();
            if (!sessionSnap.exists) {
                firebase_functions_1.logger.warn(`[payments] webhook CAPTURE.COMPLETED session not found invoiceId=${invoiceId}`);
                break;
            }
            const session = sessionSnap.data();
            if (session.status === "paid") {
                firebase_functions_1.logger.info(`[payments] webhook CAPTURE.COMPLETED already paid sessionId=${invoiceId}`);
                break;
            }
            const amountCents = Math.round(parseFloat(captureAmount.value) * 100);
            if (amountCents !== session.amountCents || captureAmount.currency_code !== session.currency) {
                firebase_functions_1.logger.error(`[payments] webhook CAPTURE.COMPLETED amount mismatch sessionId=${invoiceId} got=${amountCents}/${captureAmount.currency_code} expected=${session.amountCents}/${session.currency}`);
                break;
            }
            await grantPurchase(invoiceId, session, captureId);
            firebase_functions_1.logger.info(`[payments] webhook reconciled capture sessionId=${invoiceId} captureId=${captureId}`);
            break;
        }
        case "PAYMENT.CAPTURE.DENIED": {
            const captureId = resource["id"];
            const invoiceId = resource["invoice_id"];
            if (!invoiceId) {
                firebase_functions_1.logger.warn(`[payments] webhook CAPTURE.DENIED missing invoiceId captureId=${captureId}`);
                break;
            }
            await firestore
                .collection("paymentSessions")
                .doc(invoiceId)
                .update({ status: "cancelled", updatedAt: firestore_1.FieldValue.serverTimestamp() })
                .catch((err) => firebase_functions_1.logger.warn(`[payments] webhook CAPTURE.DENIED update failed sessionId=${invoiceId}`, err));
            firebase_functions_1.logger.info(`[payments] webhook capture denied sessionId=${invoiceId} captureId=${captureId}`);
            break;
        }
        case "PAYMENT.CAPTURE.REFUNDED":
            // Full reconciliation requires fetching the original capture (resource.links[].rel=="up")
            // and mapping invoice_id to the session. Implemented after vaulting rollout.
            firebase_functions_1.logger.info(`[payments] webhook refund received captureId=${resource["id"]}`);
            break;
        default:
            firebase_functions_1.logger.info(`[payments] webhook unhandled type=${eventType}`);
    }
}
// ─── billingPage (HTTP) ───────────────────────────────────────────────────────
// Shows the user's payment history. Requires composite Firestore index on
// paymentSessions: uid ASC + createdAt DESC.
exports.billingPage = (0, https_1.onRequest)(async (req, res) => {
    const uid = req.query.uid;
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
    const fmt = (ts) => ts ? new Date(ts.toMillis()).toLocaleDateString("en-US") : "—";
    const money = (cents, currency) => `${(cents / 100).toFixed(2)} ${currency}`;
    const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const sessionRows = sessionsSnap.docs
        .map((doc) => {
        const d = doc.data();
        return `<tr><td>${esc(doc.id.slice(0, 8))}…</td><td>${fmt(d.createdAt)}</td><td>${money(d.amountCents, d.currency)}</td><td>${esc(d.status)}</td></tr>`;
    })
        .join("") || "<tr><td colspan='4'>No payments yet.</td></tr>";
    const purchaseRows = purchasesSnap.docs
        .map((doc) => {
        const d = doc.data();
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
//# sourceMappingURL=payments.js.map