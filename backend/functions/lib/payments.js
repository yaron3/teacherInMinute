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
const FUNCTIONS_BASE_URL = "https://us-central1-teacher-in-a-moment.cloudfunctions.net";
/** Coerce a value from Firestore (may be string, number, null, undefined) to a safe integer. */
function toSafeMinutes(value) {
    const n = Math.floor(Number(value));
    return Number.isFinite(n) && n > 0 ? n : 0;
}
// ─── createCheckoutSession ────────────────────────────────────────────────────
exports.createCheckoutSession = (0, https_1.onCall)(async (req) => {
    var _a, _b, _c, _d, _e, _f, _g;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const data = req.data;
    const packageId = ((_e = (_d = (_c = (_b = data.pricingOptionId) !== null && _b !== void 0 ? _b : data.pricingOptionID) !== null && _c !== void 0 ? _c : data.packageId) !== null && _d !== void 0 ? _d : data.packageID) !== null && _e !== void 0 ? _e : data.pricingOption);
    firebase_functions_1.logger.info(`[payments] createCheckoutSession uid=${uid} packageId=${packageId !== null && packageId !== void 0 ? packageId : "(missing)"}`);
    if (!packageId)
        throw new https_1.HttpsError("invalid-argument", "Missing pricing package id");
    const packageSnap = await firestore.collection("pricing").doc(packageId).get();
    if (!packageSnap.exists)
        throw new https_1.HttpsError("not-found", "Pricing package not found");
    const pkg = packageSnap.data();
    const minutes = toSafeMinutes((_f = pkg.minutes) !== null && _f !== void 0 ? _f : pkg.minutesGranted);
    if (!pkg.priceCents || pkg.priceCents <= 0)
        throw new https_1.HttpsError("internal", "Invalid package price");
    if (!pkg.currency)
        throw new https_1.HttpsError("internal", "Invalid package currency");
    if (minutes <= 0)
        throw new https_1.HttpsError("internal", "Invalid package minutes");
    firebase_functions_1.logger.info(`[payments] package fetched packageId=${packageId} priceCents=${pkg.priceCents} currency=${pkg.currency} minutes=${minutes}`);
    const checkoutId = (0, uuid_1.v4)();
    const returnUrl = `${FUNCTIONS_BASE_URL}/paypalSuccess?checkoutId=${checkoutId}`;
    const cancelUrl = `${FUNCTIONS_BASE_URL}/paypalCancel?checkoutId=${checkoutId}`;
    const checkoutRef = firestore.collection("paymentCheckouts").doc(checkoutId);
    const checkoutDoc = {
        uid,
        packageId,
        packageType: pkg.type,
        priceCents: pkg.priceCents,
        currency: pkg.currency,
        minutes,
        status: "created",
        createdAt: firestore_1.Timestamp.now(),
        paypalOrderId: null,
    };
    await checkoutRef.set(checkoutDoc);
    let order;
    try {
        firebase_functions_1.logger.info(`[payments] PayPal createOrder checkoutId=${checkoutId} amount=${(pkg.priceCents / 100).toFixed(2)} ${pkg.currency}`);
        order = await (0, paypal_1.createOrder)({
            amountCents: pkg.priceCents,
            currency: pkg.currency,
            description: pkg.name,
            uid,
            sessionId: checkoutId,
            returnUrl,
            cancelUrl,
        });
    }
    catch (err) {
        firebase_functions_1.logger.error(`[payments] PayPal createOrder failed checkoutId=${checkoutId}`, err);
        await checkoutRef.update({ status: "cancelled", updatedAt: firestore_1.Timestamp.now() });
        throw new https_1.HttpsError("internal", "Failed to create PayPal order");
    }
    const approvalLink = (_g = order.links) === null || _g === void 0 ? void 0 : _g.find((l) => l.rel === "approve" || l.rel === "payer-action");
    if (!(approvalLink === null || approvalLink === void 0 ? void 0 : approvalLink.href)) {
        firebase_functions_1.logger.error(`[payments] no approval URL checkoutId=${checkoutId} orderId=${order.id} links=${JSON.stringify(order.links)}`);
        throw new https_1.HttpsError("internal", "PayPal did not return an approval URL");
    }
    firebase_functions_1.logger.info(`[payments] approval URL selected rel=${approvalLink.rel} href=${approvalLink.href}`);
    await checkoutRef.update({
        paypalOrderId: order.id,
        approvalUrl: approvalLink.href,
        status: "paypal_created",
        updatedAt: firestore_1.Timestamp.now(),
    });
    firebase_functions_1.logger.info(`[payments] checkout saved checkoutId=${checkoutId} paypalOrderId=${order.id}`);
    return { checkoutUrl: approvalLink.href };
});
// ─── createPaymentSettingsSession ─────────────────────────────────────────────
exports.createPaymentSettingsSession = (0, https_1.onCall)(async (req) => {
    var _a, _b;
    const uid = (_a = req.auth) === null || _a === void 0 ? void 0 : _a.uid;
    if (!uid)
        throw new https_1.HttpsError("unauthenticated", "Sign in required");
    const baseUrl = (_b = process.env.PUBLIC_BASE_URL) !== null && _b !== void 0 ? _b : FUNCTIONS_BASE_URL;
    firebase_functions_1.logger.info(`[payments] settings session uid=${uid}`);
    return { settingsUrl: `${baseUrl}/billingPage?uid=${uid}` };
});
// ─── paypalSuccess (HTTP) ─────────────────────────────────────────────────────
// PayPal redirects here after buyer approval. Captures the order, credits the
// user, then redirects to the app deep link.
exports.paypalSuccess = (0, https_1.onRequest)(async (req, res) => {
    var _a, _b, _c, _d;
    const checkoutId = req.query.checkoutId;
    const token = req.query.token; // PayPal order id
    firebase_functions_1.logger.info(`[payments] paypalSuccess checkoutId=${checkoutId} token=${token}`);
    const failRedirect = `teacherminute://payment-return?status=cancelled&checkout_id=${checkoutId !== null && checkoutId !== void 0 ? checkoutId : "unknown"}&order_id=${token !== null && token !== void 0 ? token : "unknown"}`;
    if (!checkoutId) {
        firebase_functions_1.logger.warn(`[payments] paypalSuccess missing checkoutId`);
        res.redirect(302, failRedirect);
        return;
    }
    const checkoutRef = firestore.collection("paymentCheckouts").doc(checkoutId);
    const checkoutSnap = await checkoutRef.get();
    if (!checkoutSnap.exists) {
        firebase_functions_1.logger.error(`[payments] paypalSuccess checkout not found checkoutId=${checkoutId}`);
        res.redirect(302, failRedirect);
        return;
    }
    const checkout = checkoutSnap.data();
    if (checkout.status === "completed") {
        firebase_functions_1.logger.info(`[payments] paypalSuccess already completed (idempotent) checkoutId=${checkoutId}`);
        const deepLink = `teacherminute://payment-return?status=success&order_id=${(_b = (_a = checkout.paypalOrderId) !== null && _a !== void 0 ? _a : token) !== null && _b !== void 0 ? _b : "unknown"}&checkout_id=${checkoutId}`;
        firebase_functions_1.logger.info(`[payments] paypalSuccess redirect ${deepLink}`);
        res.redirect(302, deepLink);
        return;
    }
    const orderId = (_c = token !== null && token !== void 0 ? token : checkout.paypalOrderId) !== null && _c !== void 0 ? _c : "";
    if (!orderId) {
        firebase_functions_1.logger.error(`[payments] paypalSuccess no orderId checkoutId=${checkoutId}`);
        res.redirect(302, failRedirect);
        return;
    }
    let capture;
    try {
        capture = await (0, paypal_1.captureOrder)(orderId);
        firebase_functions_1.logger.info(`[payments] paypalSuccess capture orderId=${orderId} captureId=${capture.captureId} status=${capture.orderStatus} amountCents=${capture.amountCents} currency=${capture.currency}`);
    }
    catch (err) {
        firebase_functions_1.logger.error(`[payments] paypalSuccess captureOrder failed checkoutId=${checkoutId} orderId=${orderId}`, err);
        // Webhook may have already captured and completed this checkout — check before failing.
        const recheckSnap = await checkoutRef.get();
        if (((_d = recheckSnap.data()) === null || _d === void 0 ? void 0 : _d.status) === "completed") {
            firebase_functions_1.logger.info(`[payments] paypalSuccess capture failed but checkout already completed (webhook race) checkoutId=${checkoutId}`);
            const deepLink = `teacherminute://payment-return?status=success&order_id=${orderId}&checkout_id=${checkoutId}`;
            firebase_functions_1.logger.info(`[payments] paypalSuccess redirect ${deepLink}`);
            res.redirect(302, deepLink);
            return;
        }
        res.redirect(302, failRedirect);
        return;
    }
    if (capture.orderStatus !== "COMPLETED") {
        firebase_functions_1.logger.error(`[payments] paypalSuccess unexpected capture status checkoutId=${checkoutId} status=${capture.orderStatus}`);
        res.redirect(302, failRedirect);
        return;
    }
    const userRef = firestore.collection("users").doc(checkout.uid);
    try {
        await firestore.runTransaction(async (tx) => {
            var _a, _b;
            const freshSnap = await tx.get(checkoutRef);
            if (((_a = freshSnap.data()) === null || _a === void 0 ? void 0 : _a.status) === "completed") {
                firebase_functions_1.logger.info(`[payments] paypalSuccess transaction already completed checkoutId=${checkoutId}`);
                return;
            }
            const now = firestore_1.Timestamp.now();
            tx.update(checkoutRef, {
                status: "completed",
                completedAt: now,
                updatedAt: now,
                paypalOrderId: orderId,
                paypalCaptureId: capture.captureId,
            });
            tx.set(userRef, {
                remainingMinutes: firestore_1.FieldValue.increment(toSafeMinutes(checkout.minutes)),
                totalMinutes: firestore_1.FieldValue.increment(toSafeMinutes(checkout.minutes)),
            }, { merge: true });
            const purchaseRef = userRef.collection("purchases").doc(checkoutId);
            tx.set(purchaseRef, {
                pricingOptionId: checkout.packageId,
                provider: "paypal",
                amountCents: checkout.priceCents,
                currency: checkout.currency,
                type: (_b = checkout.packageType) !== null && _b !== void 0 ? _b : "pay_as_you_go",
                status: "active",
                purchasedAt: now,
                updatedAt: now,
                minutesPurchased: toSafeMinutes(checkout.minutes),
                minutesRemaining: toSafeMinutes(checkout.minutes),
                minutesUsed: 0,
            }, { merge: true });
        });
    }
    catch (err) {
        firebase_functions_1.logger.error(`[payments] paypalSuccess transaction failed checkoutId=${checkoutId}`, err);
        res.redirect(302, failRedirect);
        return;
    }
    firebase_functions_1.logger.info(`[payments] paypalSuccess credited uid=${checkout.uid} minutes=${checkout.minutes} checkoutId=${checkoutId}`);
    const deepLink = `teacherminute://payment-return?status=success&order_id=${orderId}&checkout_id=${checkoutId}`;
    firebase_functions_1.logger.info(`[payments] paypalSuccess redirect ${deepLink}`);
    res.redirect(302, deepLink);
});
// ─── paypalCancel (HTTP) ──────────────────────────────────────────────────────
exports.paypalCancel = (0, https_1.onRequest)(async (req, res) => {
    const checkoutId = req.query.checkoutId;
    const token = req.query.token;
    firebase_functions_1.logger.info(`[payments] paypalCancel checkoutId=${checkoutId} token=${token}`);
    if (checkoutId) {
        firestore
            .collection("paymentCheckouts")
            .doc(checkoutId)
            .update({ status: "cancelled", updatedAt: firestore_1.Timestamp.now() })
            .catch((err) => firebase_functions_1.logger.warn(`[payments] paypalCancel update failed checkoutId=${checkoutId}`, err));
    }
    const deepLink = `teacherminute://payment-return?status=cancelled&checkout_id=${checkoutId !== null && checkoutId !== void 0 ? checkoutId : "unknown"}`;
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
    // PayPal sandbox signature verification is unreliable — bypass it in sandbox.
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
            const invoiceId = resource["invoice_id"]; // == checkoutId
            const captureAmount = resource["amount"];
            if (!invoiceId || !captureAmount) {
                firebase_functions_1.logger.warn(`[payments] webhook CAPTURE.COMPLETED missing fields captureId=${captureId}`);
                break;
            }
            const checkoutRef = firestore.collection("paymentCheckouts").doc(invoiceId);
            const checkoutSnap = await checkoutRef.get();
            if (!checkoutSnap.exists) {
                firebase_functions_1.logger.warn(`[payments] webhook CAPTURE.COMPLETED checkout not found checkoutId=${invoiceId}`);
                break;
            }
            const checkout = checkoutSnap.data();
            if (checkout.status === "completed") {
                firebase_functions_1.logger.info(`[payments] webhook CAPTURE.COMPLETED already completed checkoutId=${invoiceId}`);
                break;
            }
            const amountCents = Math.round(parseFloat(captureAmount.value) * 100);
            if (amountCents !== checkout.priceCents ||
                captureAmount.currency_code !== checkout.currency) {
                firebase_functions_1.logger.error(`[payments] webhook CAPTURE.COMPLETED amount mismatch checkoutId=${invoiceId} got=${amountCents}/${captureAmount.currency_code} expected=${checkout.priceCents}/${checkout.currency}`);
                break;
            }
            const userRef = firestore.collection("users").doc(checkout.uid);
            await firestore.runTransaction(async (tx) => {
                var _a, _b;
                const fresh = await tx.get(checkoutRef);
                if (((_a = fresh.data()) === null || _a === void 0 ? void 0 : _a.status) === "completed")
                    return;
                const now = firestore_1.Timestamp.now();
                tx.update(checkoutRef, {
                    status: "completed",
                    completedAt: now,
                    updatedAt: now,
                    paypalCaptureId: captureId,
                });
                tx.set(userRef, {
                    remainingMinutes: firestore_1.FieldValue.increment(toSafeMinutes(checkout.minutes)),
                    totalMinutes: firestore_1.FieldValue.increment(toSafeMinutes(checkout.minutes)),
                }, { merge: true });
                const purchaseRef = userRef.collection("purchases").doc(invoiceId);
                tx.set(purchaseRef, {
                    pricingOptionId: checkout.packageId,
                    provider: "paypal",
                    amountCents: checkout.priceCents,
                    currency: checkout.currency,
                    type: (_b = checkout.packageType) !== null && _b !== void 0 ? _b : "pay_as_you_go",
                    status: "active",
                    purchasedAt: now,
                    updatedAt: now,
                    minutesPurchased: toSafeMinutes(checkout.minutes),
                    minutesRemaining: toSafeMinutes(checkout.minutes),
                    minutesUsed: 0,
                }, { merge: true });
            });
            firebase_functions_1.logger.info(`[payments] webhook reconciled checkoutId=${invoiceId} captureId=${captureId} uid=${checkout.uid} minutes=${checkout.minutes}`);
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
                .collection("paymentCheckouts")
                .doc(invoiceId)
                .update({ status: "cancelled", updatedAt: firestore_1.Timestamp.now() })
                .catch((err) => firebase_functions_1.logger.warn(`[payments] webhook CAPTURE.DENIED update failed checkoutId=${invoiceId}`, err));
            firebase_functions_1.logger.info(`[payments] webhook capture denied checkoutId=${invoiceId} captureId=${captureId}`);
            break;
        }
        case "PAYMENT.CAPTURE.REFUNDED":
            firebase_functions_1.logger.info(`[payments] webhook refund received captureId=${resource["id"]}`);
            break;
        default:
            firebase_functions_1.logger.info(`[payments] webhook unhandled type=${eventType}`);
    }
}
// ─── billingPage (HTTP) ───────────────────────────────────────────────────────
exports.billingPage = (0, https_1.onRequest)(async (req, res) => {
    const uid = req.query.uid;
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
    const fmt = (ts) => ts ? new Date(ts.toMillis()).toLocaleDateString("en-US") : "—";
    const money = (cents, currency) => `${(cents / 100).toFixed(2)} ${currency}`;
    const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    const rows = checkoutsSnap.docs
        .map((doc) => {
        const d = doc.data();
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
//# sourceMappingURL=payments.js.map