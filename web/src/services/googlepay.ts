import { httpsCallable } from "firebase/functions";
import { functions } from "./firebase";
import { currencyCode } from "./purchase";

// Google Pay on the web, as Google's tutorial lays it out
// (developers.google.com/pay/api/web): pay.js, a PaymentsClient, Google's own
// button once isReadyToPay says yes, and loadPaymentData straight from the
// tap. The gateway is Braintree: the token Google returns carries a Braintree
// nonce, which the backend charges (confirmGooglePayPayment), as the Android
// app's Google Pay does.

/* Just what this file uses of google.payments.api. */
interface PaymentsClient {
  isReadyToPay(request: object): Promise<{ result: boolean }>;
  createButton(options: object): HTMLElement;
  loadPaymentData(request: object): Promise<PaymentData>;
}
interface PaymentData {
  paymentMethodData: { tokenizationData: { token: string } };
}
type GoogleApi = { payments: { api: { PaymentsClient: new (options: { environment: string }) => PaymentsClient } } };

export interface GooglePayConfig {
  clientToken: string;
  environment: "TEST" | "PRODUCTION";
  merchantName: string;
  countryCode: string;
  googleMerchantId?: string;
}

const BASE_REQUEST = { apiVersion: 2, apiVersionMinor: 0 };

/** Cards Google Pay may offer. Israeli Braintree accounts take Visa,
 *  Mastercard and Amex. */
const BASE_CARD_METHOD = {
  type: "CARD",
  parameters: {
    allowedAuthMethods: ["PAN_ONLY", "CRYPTOGRAM_3DS"],
    allowedCardNetworks: ["VISA", "MASTERCARD", "AMEX"],
  },
};

let script: Promise<GoogleApi> | null = null;
function loadScript(): Promise<GoogleApi> {
  script ??= new Promise<GoogleApi>((resolve, reject) => {
    const tag = document.createElement("script");
    tag.src = "https://pay.google.com/gp/p/js/pay.js";
    tag.async = true;
    tag.onload = () => {
      const google = (window as unknown as { google?: GoogleApi }).google;
      if (google?.payments?.api) resolve(google);
      else reject(new Error("pay.js loaded without its API"));
    };
    tag.onerror = () => reject(new Error("pay.js failed to load"));
    document.head.appendChild(tag);
  }).catch((e) => {
    script = null;
    throw e;
  });
  return script;
}

export interface GooglePay {
  client: PaymentsClient;
  config: GooglePayConfig;
}

const ready = new Map<string, Promise<GooglePay | null>>();

/** Google Pay for this currency, or null when the browser or the backend
 *  cannot take it. Read once per currency. */
export function prepareGooglePay(currency: string): Promise<GooglePay | null> {
  const code = currencyCode(currency);
  let pending = ready.get(code);
  if (!pending) {
    pending = (async () => {
      const [google, { data: config }] = await Promise.all([
        loadScript(),
        httpsCallable<object, GooglePayConfig>(functions, "getGooglePayWebConfig")({ currency: code }),
      ]);
      const client = new google.payments.api.PaymentsClient({ environment: config.environment });
      const { result } = await client.isReadyToPay({ ...BASE_REQUEST, allowedPaymentMethods: [BASE_CARD_METHOD] });
      return result ? { client, config } : null;
    })().catch((e) => {
      console.warn("[googlePay] unavailable", e);
      ready.delete(code);
      return null;
    });
    ready.set(code, pending);
  }
  return pending;
}

/** Google's button (brand rules: Google draws it). */
export function googlePayButton(pay: GooglePay, onClick: () => void, language: "english" | "hebrew"): HTMLElement {
  return pay.client.createButton({
    onClick,
    allowedPaymentMethods: [BASE_CARD_METHOD],
    buttonColor: "white",
    buttonType: "buy",
    buttonSizeMode: "fill",
    buttonLocale: language === "hebrew" ? "he" : "en",
  });
}

/** The gateway parameters for Braintree, from its client token: the merchant
 *  id and the authorization fingerprint, as braintree-web's googlePayment
 *  builds them. */
function braintreeTokenization(clientToken: string) {
  const decoded = JSON.parse(atob(clientToken)) as { authorizationFingerprint: string; configUrl: string };
  const merchantId = /\/merchants\/([^/]+)\//.exec(decoded.configUrl)?.[1];
  if (!merchantId) throw new Error("no Braintree merchant id in the client token");
  return {
    type: "PAYMENT_GATEWAY",
    parameters: {
      gateway: "braintree",
      "braintree:merchantId": merchantId,
      "braintree:apiVersion": "v1",
      "braintree:sdkVersion": "3.111.0",
      "braintree:metadata": JSON.stringify({ source: "client", integration: "custom", platform: "web" }),
      "braintree:authorizationFingerprint": decoded.authorizationFingerprint,
    },
  };
}

/** Thrown when the buyer closes Google's sheet. */
export class GooglePayCancelled extends Error {}

/** Opens Google's sheet for the price; must run straight from the tap.
 *  Resolves to the Braintree nonce inside Google's token. */
export async function requestGooglePayNonce(
  pay: GooglePay,
  price: { cents: number; currency: string },
): Promise<string> {
  const { config } = pay;
  let data: PaymentData;
  try {
    data = await pay.client.loadPaymentData({
      ...BASE_REQUEST,
      allowedPaymentMethods: [{ ...BASE_CARD_METHOD, tokenizationSpecification: braintreeTokenization(config.clientToken) }],
      transactionInfo: {
        totalPriceStatus: "FINAL",
        totalPrice: (price.cents / 100).toFixed(2),
        currencyCode: currencyCode(price.currency),
        countryCode: config.countryCode,
      },
      merchantInfo: {
        merchantName: config.merchantName,
        ...(config.googleMerchantId ? { merchantId: config.googleMerchantId } : {}),
      },
    });
  } catch (e) {
    if ((e as { statusCode?: string })?.statusCode === "CANCELED") throw new GooglePayCancelled();
    throw e;
  }
  const token = JSON.parse(data.paymentMethodData.tokenizationData.token) as { androidPayCards?: { nonce?: string }[] };
  const nonce = token.androidPayCards?.[0]?.nonce;
  if (!nonce) throw new Error("no Braintree nonce in the Google Pay token");
  return nonce;
}

/** Opens the checkout once the buyer approved, and has the backend charge the
 *  nonce for the checkout's own price (never the page's). */
export async function chargeGooglePay(packageId: string, nonce: string): Promise<{ checkoutId: string }> {
  const { data } = await httpsCallable<object, { checkoutId?: string; checkoutUrl?: string }>(functions, "createGooglePayCheckout")({
    pricingOptionId: packageId,
    platform: "web",
    processor: "braintree",
  });
  if (!data.checkoutId || data.checkoutUrl) throw new Error("Google Pay checkout did not open on Braintree");
  await httpsCallable(functions, "confirmGooglePayPayment")({ checkoutId: data.checkoutId, nonce });
  return { checkoutId: data.checkoutId };
}
