"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.getAccessToken = getAccessToken;
exports.createOrder = createOrder;
exports.captureOrder = captureOrder;
exports.verifyWebhookSignature = verifyWebhookSignature;
const firebase_functions_1 = require("firebase-functions");
function paypalBase() {
    return process.env.PAYPAL_ENV === "live"
        ? "https://api-m.paypal.com"
        : "https://api-m.sandbox.paypal.com";
}
let cachedToken = null;
async function getAccessToken() {
    var _a, _b;
    const now = Date.now();
    if (cachedToken && cachedToken.expiresAt > now + 60000) {
        return cachedToken.token;
    }
    const clientId = (_a = process.env.PAYPAL_CLIENT_ID) !== null && _a !== void 0 ? _a : "";
    const clientSecret = (_b = process.env.PAYPAL_CLIENT_SECRET) !== null && _b !== void 0 ? _b : "";
    if (!clientId || !clientSecret) {
        throw new Error("PAYPAL_CLIENT_ID and PAYPAL_CLIENT_SECRET must be configured");
    }
    const credentials = Buffer.from(`${clientId}:${clientSecret}`).toString("base64");
    const res = await fetch(`${paypalBase()}/v1/oauth2/token`, {
        method: "POST",
        headers: {
            Authorization: `Basic ${credentials}`,
            "Content-Type": "application/x-www-form-urlencoded",
        },
        body: "grant_type=client_credentials",
    });
    if (!res.ok) {
        firebase_functions_1.logger.error(`[paypal] token request failed status=${res.status}`);
        throw new Error("Failed to obtain PayPal access token");
    }
    const data = (await res.json());
    cachedToken = { token: data.access_token, expiresAt: now + data.expires_in * 1000 };
    return cachedToken.token;
}
async function createOrder(params) {
    const token = await getAccessToken();
    const value = (params.amountCents / 100).toFixed(2);
    const res = await fetch(`${paypalBase()}/v2/checkout/orders`, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
            "PayPal-Request-Id": params.sessionId,
        },
        body: JSON.stringify({
            intent: "CAPTURE",
            purchase_units: [
                {
                    amount: { currency_code: params.currency, value },
                    custom_id: params.uid,
                    invoice_id: params.sessionId,
                    description: params.description,
                },
            ],
            application_context: {
                return_url: params.returnUrl,
                cancel_url: params.cancelUrl,
                user_action: "PAY_NOW",
            },
        }),
    });
    if (!res.ok) {
        firebase_functions_1.logger.error(`[paypal] createOrder failed status=${res.status}`);
        throw new Error("Failed to create PayPal order");
    }
    return (await res.json());
}
async function captureOrder(orderId) {
    var _a, _b, _c;
    const token = await getAccessToken();
    const res = await fetch(`${paypalBase()}/v2/checkout/orders/${orderId}/capture`, {
        method: "POST",
        headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
        },
    });
    if (!res.ok) {
        firebase_functions_1.logger.error(`[paypal] captureOrder failed orderId=${orderId} status=${res.status}`);
        throw new Error("Failed to capture PayPal order");
    }
    const data = (await res.json());
    const capture = (_c = (_b = (_a = data.purchase_units[0]) === null || _a === void 0 ? void 0 : _a.payments) === null || _b === void 0 ? void 0 : _b.captures) === null || _c === void 0 ? void 0 : _c[0];
    if (!capture)
        throw new Error("No capture in PayPal response");
    return {
        orderId: data.id,
        captureId: capture.id,
        orderStatus: data.status,
        amountCents: Math.round(parseFloat(capture.amount.value) * 100),
        currency: capture.amount.currency_code,
    };
}
async function verifyWebhookSignature(params) {
    try {
        const token = await getAccessToken();
        const res = await fetch(`${paypalBase()}/v1/notifications/verify-webhook-signature`, {
            method: "POST",
            headers: {
                Authorization: `Bearer ${token}`,
                "Content-Type": "application/json",
            },
            body: JSON.stringify({
                transmission_id: params.transmissionId,
                transmission_time: params.transmissionTime,
                cert_url: params.certUrl,
                auth_algo: params.authAlgo,
                transmission_sig: params.transmissionSig,
                webhook_id: params.webhookId,
                webhook_event: params.webhookEvent,
            }),
        });
        if (!res.ok) {
            firebase_functions_1.logger.error(`[paypal] webhook verify failed status=${res.status}`);
            return false;
        }
        const data = (await res.json());
        return data.verification_status === "SUCCESS";
    }
    catch (err) {
        firebase_functions_1.logger.error("[paypal] webhook verify threw", err);
        return false;
    }
}
//# sourceMappingURL=paypal.js.map