import { logger } from "firebase-functions";

function paypalBase(): string {
  return process.env.PAYPAL_ENV === "live"
    ? "https://api-m.paypal.com"
    : "https://api-m.sandbox.paypal.com";
}

interface CachedToken {
  token: string;
  expiresAt: number;
}

let cachedToken: CachedToken | null = null;

export async function getAccessToken(): Promise<string> {
  const now = Date.now();
  if (cachedToken && cachedToken.expiresAt > now + 60_000) {
    return cachedToken.token;
  }

  const clientId = process.env.PAYPAL_CLIENT_ID ?? "";
  const clientSecret = process.env.PAYPAL_CLIENT_SECRET ?? "";
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
    logger.error(`[paypal] token request failed status=${res.status}`);
    throw new Error("Failed to obtain PayPal access token");
  }

  const data = (await res.json()) as { access_token: string; expires_in: number };
  cachedToken = { token: data.access_token, expiresAt: now + data.expires_in * 1000 };
  return cachedToken.token;
}

export interface CreateOrderParams {
  amountCents: number;
  currency: string;
  description: string;
  uid: string;
  sessionId: string;
  returnUrl: string;
  cancelUrl: string;
}

export interface PayPalLink {
  rel: string;
  href: string;
  method: string;
}

export interface PayPalOrderResult {
  id: string;
  status?: string;
  links: PayPalLink[];
  [key: string]: unknown;
}

export async function createOrder(params: CreateOrderParams): Promise<PayPalOrderResult> {
  const token = await getAccessToken();
  const value = (params.amountCents / 100).toFixed(2);

  const orderBody = {
    intent: "CAPTURE",
    purchase_units: [
      {
        amount: { currency_code: params.currency, value },
        custom_id: params.uid,
        invoice_id: params.sessionId,
        description: params.description,
      },
    ],
    payment_source: {
      paypal: {
        experience_context: {
          return_url: params.returnUrl,
          cancel_url: params.cancelUrl,
          user_action: "PAY_NOW",
        },
      },
    },
  };

  logger.info(
    `[paypal] createOrder request sessionId=${params.sessionId} uid=${params.uid} amount=${value} ${params.currency} returnUrl=${params.returnUrl}`
  );

  const res = await fetch(`${paypalBase()}/v2/checkout/orders`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
      "PayPal-Request-Id": params.sessionId,
    },
    body: JSON.stringify(orderBody),
  });

  if (!res.ok) {
    const errBody = await res.text().catch(() => "(unreadable)");
    logger.error(`[paypal] createOrder failed status=${res.status} body=${errBody}`);
    throw new Error("Failed to create PayPal order");
  }

  const data = (await res.json()) as PayPalOrderResult;
  logger.info(
    `[paypal] createOrder response orderId=${data.id} status=${data.status} linksCount=${data.links?.length ?? 0}`
  );
  return data;
}

export interface CaptureResult {
  orderId: string;
  captureId: string;
  orderStatus: string;
  amountCents: number;
  currency: string;
}

interface PayPalCaptureResponse {
  id: string;
  status: string;
  purchase_units: Array<{
    payments: {
      captures: Array<{
        id: string;
        status: string;
        amount: { value: string; currency_code: string };
      }>;
    };
  }>;
}

export async function captureOrder(orderId: string): Promise<CaptureResult> {
  const token = await getAccessToken();

  const res = await fetch(`${paypalBase()}/v2/checkout/orders/${orderId}/capture`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
  });

  if (!res.ok) {
    logger.error(`[paypal] captureOrder failed orderId=${orderId} status=${res.status}`);
    throw new Error("Failed to capture PayPal order");
  }

  const data = (await res.json()) as PayPalCaptureResponse;
  const capture = data.purchase_units[0]?.payments?.captures?.[0];
  if (!capture) throw new Error("No capture in PayPal response");

  return {
    orderId: data.id,
    captureId: capture.id,
    orderStatus: data.status,
    amountCents: Math.round(parseFloat(capture.amount.value) * 100),
    currency: capture.amount.currency_code,
  };
}

interface VerifyParams {
  transmissionId: string;
  transmissionTime: string;
  certUrl: string;
  authAlgo: string;
  transmissionSig: string;
  webhookId: string;
  webhookEvent: Record<string, unknown>;
}

export async function verifyWebhookSignature(params: VerifyParams): Promise<boolean> {
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
      logger.error(`[paypal] webhook verify failed status=${res.status}`);
      return false;
    }

    const data = (await res.json()) as { verification_status: string };
    return data.verification_status === "SUCCESS";
  } catch (err) {
    logger.error("[paypal] webhook verify threw", err);
    return false;
  }
}
