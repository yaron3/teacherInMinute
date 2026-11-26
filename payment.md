# Payments — what is left to support every method

Status as of 2026-11-26. Covers the web client (`web/`), the iOS and Android
apps (`teacher-minute/`) and the backend (`backend/Firebase/functions`).

## Where each method stands

| Method | Processor | Web | iOS app | Android app | Staging | Production |
|---|---|---|---|---|---|---|
| Credit card | Tranzila (hosted fields) | In-app sheet | Browser page | Browser page | Works; real card not yet tried in the web sheet | Tranzila is set up; web not deployed |
| PayPal | PayPal Orders v2 | PayPal's own buttons (JS SDK) | Redirect | Redirect | **Verified end to end** (sandbox payment captured, 60 minutes credited) | **`PAYPAL_ENV=sandbox` — takes no real money** |
| Apple Pay | Tranzila page (web, and apps when `TRANZILA_WALLETS` lists it); else Braintree | Safari only, in the sheet | Native sheet (Braintree) or Tranzila page | — | Wallet page opens; button not yet seen in Safari | `TRANZILA_WALLETS` empty; Braintree is sandbox |
| Google Pay | Braintree (web, Google Pay API); Tranzila page or Braintree in the app | **Hidden** (`enable_google_pay=false`) | — | **Hidden** (`enable_google_pay=false`) | Built, not tested | Needs Google's approval + live Braintree |
| Bit | none | — | — | — | Backend rejects it | Not started |

Current production settings on the functions (read 2026-11-26):

- `PAYPAL_ENV=sandbox`, `BRAINTREE_ENV=sandbox`, `TRANZILA_WALLETS=` (empty).
- Tranzila keys, terminal and notify key are set.
- Production has no `functions/.env.teacher-in-a-moment` of its own; it reads
  the shared `functions/.env`. Staging overrides it with
  `functions/.env.teacher-in-a-moment-staging`.

## 1. Deploy what is already built

Nothing below takes effect until it is deployed. Staging is up to date except
the Google Pay pieces; production has none of the web payment work.

1. **Commit** the open work (Google Pay on the web, the `enable_google_pay` flag
   in the apps and on the web, the PayPal button class fix, `payment.md`).
2. **Remote Config** — `enable_google_pay=false`:
   - Staging: **done** 2026-11-26 (template version 6). Do not run
     `firebase deploy --only remoteconfig -P staging`: `remote_config_tim.json`
     is production's template, and its conditions name production's app IDs,
     which staging rejects. Edit staging in the console, or add keys to its
     live template through the REST API.
   - Production: the live template matched the file exactly on 2026-11-26
     (values and conditions) except the new key, so this adds only that:

     ```bash
     cd backend/Firebase && npx firebase deploy --only remoteconfig -P prod
     ```

     It replaces the whole live template, so compare again first if the
     console was edited since (`npx firebase remoteconfig:get -P prod`).
3. **Functions, then hosting**, in that order, per project:

   ```bash
   npx firebase deploy --only functions:createCheckoutSession,functions:createApplePayCheckout,functions:createGooglePayCheckout,functions:getGooglePayWebConfig,functions:confirmGooglePayPayment,functions:getPayPalWebConfig,functions:capturePayPalOrder,functions:payCardCheckout,functions:tranzilaCheckout,functions:tranzilaCharge,functions:tranzilaCheckoutStatus,functions:paypalSuccess,functions:paypalCancel -P prod
   ```

   ```bash
   npx firebase deploy --only hosting -P prod
   ```

4. **App releases** — the `enable_google_pay` gate is in the apps' code
   (`PaymentMethod.configuredForCheckout`), so it reaches users with the next
   App Store / Google Play build. Until then, older Android builds still show
   Google Pay.

## 2. Credit card (Tranzila)

- [ ] **Pay with a real card in the web sheet on staging.** The fix for Pay
      hanging (`returnTo: "parent"`, Tranzila's control frame answered
      `window.top`) was verified with empty fields only. Confirm a real
      charge lands: `tranzilaCharge` in the logs, the checkout `completed`,
      minutes added, the sheet closes on "Payment received".
- [ ] **Decline path** — a declined card shows Tranzila's message and the Pay
      button comes back.
- [ ] **3-D Secure** — if the terminal challenges cards, confirm the challenge
      opens and completes inside the sheet (Tranzila's script positions it in
      the page; it may need more room than the 760px sheet).
- [ ] Optional: set `TRANZILA_VAT_PERCENT` if invoices must show VAT (empty
      on both projects).

## 3. PayPal

- [ ] **Go live.** Production runs `PAYPAL_ENV=sandbox`, so production PayPal
      orders go to sandbox.paypal.com and take no money. In the PayPal
      developer dashboard, switch to **Live**, create (or open) the live app,
      and set in production's functions env:
      `PAYPAL_ENV=live`, `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET` (live
      pair), and `PAYPAL_WEBHOOK_ID` for a live webhook pointing at
      `https://us-central1-teacher-in-a-moment.cloudfunctions.net/paypalWebhook`
      (events the backend handles: `CHECKOUT.ORDER.APPROVED`,
      `PAYMENT.CAPTURE.COMPLETED`, `PAYMENT.CAPTURE.DENIED`,
      `PAYMENT.CAPTURE.REFUNDED`).
- [ ] Confirm the live PayPal account accepts **ILS**.
- [ ] After going live, one small real purchase from the web and from each
      app, then refund it.
- Note: the web loads PayPal's script with the client id from
  `getPayPalWebConfig`, so it switches with the backend — no web change.

## 4. Apple Pay

Two routes exist; pick one for production.

**A. Through Tranzila's page (what the web uses)**

- [ ] Ask Tranzila to enable **Apple Pay on the production terminal** (and the
      staging one if separate). Tranzila's docs say Apple Pay has no sandbox —
      testing is in production.
- [ ] Confirm `backend/Firebase/public/.well-known/apple-developer-merchantid-domain-association`
      is Tranzila's file for `teacher-in-a-moment.web.app` (and the staging
      domain), and that Tranzila registered those domains with Apple.
- [ ] Set `TRANZILA_WALLETS=apple_pay` (or `apple_pay,google_pay`) in
      production's functions env and redeploy `createApplePayCheckout`.
      This also moves the **iOS app's** Apple Pay to the Tranzila page.
- [ ] Test in Safari on a Mac and an iPhone with a real card in Wallet: the
      Apple Pay button appears on the page in the sheet, payment completes,
      `tranzilaNotify` credits the minutes.

**B. Through Braintree (the iOS app's native sheet today)**

- [ ] Needs a live Braintree account (`BRAINTREE_ENV=production`) with Apple
      Pay enabled and the `merchant.com.yaronj.tim` certificate uploaded to
      Braintree. Web does not use this route.

## 5. Google Pay (hidden until done)

Chosen route: Google Pay API for the web with **Braintree** as the gateway
(Tranzila documents no server API for a Google Pay token).

- [ ] **Braintree live account** (braintreepayments.com), with Google Pay
      enabled under Settings → Processing, and an **ILS** merchant account.
- [ ] **Google's approval** in the Google Pay & Wallet Console
      (https://pay.google.com/business/console):
      1. Business profile, accept the Google Pay API Terms and Acceptable Use
         Policy; copy the **Merchant ID** (`BCR2DN…`).
      2. Google Pay API → add website `https://teacher-in-a-moment.web.app`,
         integration type **Gateway**.
      3. Upload screenshots of the flow in TEST mode (packages, Google Pay
         chosen, the Google Pay sheet open, the "Payment received" message).
      4. Submit and wait for approval.
- [ ] Production functions env (a new `functions/.env.teacher-in-a-moment`
      so staging stays on sandbox): `BRAINTREE_ENV=production`, the live
      `BRAINTREE_MERCHANT_ID` / `BRAINTREE_PUBLIC_KEY` / `BRAINTREE_PRIVATE_KEY`,
      `BRAINTREE_MERCHANT_ACCOUNT_ILS`, `GOOGLE_PAY_MERCHANT_ID`. Note that
      `BRAINTREE_ENV=production` also moves the apps' native Apple Pay and
      Google Pay to the live account.
- [ ] Test on staging first: set `enable_google_pay=true` under a staging
      condition (or on staging's template), pay with Google's TEST cards in
      Chrome, check `confirmGooglePayPayment` credits the minutes.
- [ ] Android app: decide whether its Google Pay stays on Braintree's native
      sheet or uses the Tranzila page (`TRANZILA_WALLETS` lists
      `google_pay`); test with a real card.
- [ ] Flip `enable_google_pay=true` in production Remote Config.
- Open question for Tranzila: whether their Transactions API accepts a raw
  Google Pay token (`gateway: "tranzila"`), and the `gatewayMerchantId` to
  use. If yes, Google Pay could move to Tranzila like the cards.

## 6. Bit

- [ ] Not implemented: `backend/Firebase/functions/src/bit.ts` is a stub and
      `createCheckoutSession` rejects `bit`. Needs an Israeli PSP that offers
      Bit (Tranzila offers Bit through hosted fields — `chargeBit` — so this
      may be the shortest path), then a web method and the apps'
      `PaymentMethod.availableForCurrentPlatform`.

## 7. Housekeeping

- [ ] Unpaid checkouts from testing stay in `paymentCheckouts` with status
      `created`, `tranzila_created` or `paypal_created`. They do nothing;
      clean them up or add a scheduled job that cancels checkouts older than a
      day.
- [ ] The web caches itself as a PWA: after a hosting deploy, an open tab
      needs a reload or two to pick up the new version. Consider prompting to
      reload when a new service worker is waiting.
- [ ] Revoke the LiveKit development key in `functions/.env.local` (unrelated
      to payments, still pending from earlier).

## Reference

- Backend: `backend/Firebase/functions/src/payments.ts` (checkouts, PayPal
  capture, wallet routing, Tranzila page), `tranzila.ts`, `paypal.ts`,
  `braintree.ts`.
- Web: `web/src/services/purchase.ts`, `web/src/services/googlepay.ts`,
  `web/src/screens/BuyMinutes.tsx`, `web/public/payment-return.html`; details
  in `web/README.md`.
- Apps: `teacher-minute/Sources/TeacherMinute/Model/PaymentMethod.swift`,
  `ViewModel/StudentHomeViewModel.swift` (`loadPaymentMethods`).
