# In-app credit card form (abandoned)

Parked here on 2026-08-13. These files were the remnants of an attempt to
collect card details inside the app instead of on PayPal's hosted page. That
direction was reverted; the shipping `credit_card` method opens the hosted
`payCardCheckout` page in the browser.

Kept rather than deleted only as a reference for the Braintree GraphQL
tokenization approach, which avoids the iOS-only Braintree SDK so the same
code path could work on Android through Skip.

## Why they were removed

- Nothing referenced them. No view presented a card form, and no file under
  `Sources/` mentioned `CreditCardEntry` or `BraintreeCardService`.
- Their backend halves were never written: the service calls
  `createCardCheckout` and `confirmCardPayment`, neither of which exists in
  `backend/Firebase/functions/src`.
- Their tests never ran. No Xcode scheme has a test action and `swift test`
  fails on macOS for this package.
- They were still being compiled into every build, because SwiftPM includes
  every file under `Sources/` regardless of whether it is referenced or
  tracked by git — 429 lines of dead code, including a hand-rolled tokenizer
  handling raw card numbers.

## If you revive this

`createCardCheckout` and `confirmCardPayment` need to be written first; model
them on the wallet pair in `payments.ts` (`startWalletCheckout` /
`confirmWalletPayment`), which already turns a Braintree nonce into a charge.
Note that the hosted-page route needs PayPal's Advanced Credit and Debit Card
Payments enabled, whereas this route would settle through Braintree instead
and so sidestep that approval entirely.
