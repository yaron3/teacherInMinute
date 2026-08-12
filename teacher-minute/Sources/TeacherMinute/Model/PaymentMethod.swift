//
//  PaymentMethod.swift
//  teacher-minute
//
//  The checkout payment methods a student can choose from. These map to the
//  PayPal checkout `payment_source` supported by the backend `createCheckoutSession`
//  callable: the default PayPal flow, the Apple Pay and Google Pay wallets, and
//  credit/debit card via a hosted PayPal Advanced Card Payments page.
//

import Foundation

enum PaymentMethod: String, CaseIterable {
    case paypal
    case applePay = "apple_pay"
    case googlePay = "google_pay"
    case creditCard = "credit_card"
    // Bit needs a separate Israeli PSP integration (it isn't a PayPal wallet) —
    // see backend/Firebase/functions/src/bit.ts. The backend currently rejects
    // it with a clear "not available yet" error, so it stays out of
    // `availableForCurrentPlatform` until a provider is wired up.
    case bit

    /// The payment methods to offer for the given platform right now. PayPal,
    /// and credit card are always available (credit card opens a hosted PayPal
    /// card-entry page in the system browser); Apple Pay is iOS-only and Google
    /// Pay is Android-only (the backend rejects Apple Pay on Android, and each
    /// wallet only completes in its native browser). Bit is added here once the
    /// backend supports it.
    static var availableForCurrentPlatform: [PaymentMethod] {
#if os(Android)
        [.paypal, .googlePay, .creditCard]
#else
        [.paypal, .applePay, .creditCard]
#endif
    }

    /// The payment methods to offer at checkout, driven by the `payment_methods`
    /// Remote Config key (platform targeting — iOS vs Android — is handled by
    /// Remote Config conditions on that key). Unknown raw values are dropped; if
    /// the key is missing, empty, or lists no recognized method, the built-in
    /// `availableForCurrentPlatform` default is used.
    @MainActor
    static func configuredForCheckout() -> [PaymentMethod] {
        let raw = RemoteConfigService.shared.getStringArray(RemoteConfigKey.paymentMethods.rawValue)
        let parsed = raw.compactMap { PaymentMethod(rawValue: $0) }
        return parsed.isEmpty ? availableForCurrentPlatform : parsed
    }

    /// Currencies Apple Pay can actually process — must match the
    /// `BRAINTREE_MERCHANT_ACCOUNT_<CURRENCY>` vars declared in functions/.env.
    /// Offering Apple Pay for any other currency would let the
    /// buyer tap it and hit a dead-end "not supported yet" error, so it must be
    /// filtered out of the picker per pricing option, not just rejected server-side.
    private static let applePaySupportedCurrencies: Set<String> = ["USD", "ILS"]

    /// Filters `methods` down to what's actually usable for a given pricing
    /// option's currency — currently only affects Apple Pay.
    static func supported(_ methods: [PaymentMethod], forCurrency currency: String) -> [PaymentMethod] {
        guard !applePaySupportedCurrencies.contains(currency) else { return methods }
        return methods.filter { $0 != .applePay }
    }

    /// The wallet override string the backend expects, or `nil` for the default
    /// PayPal flow. The backend rejects the request if it receives a
    /// `paymentMethod` it doesn't recognize (including "paypal"), so the default
    /// flow must send no value at all.
    var walletParameter: String? {
        switch self {
        case .paypal:                              return nil
        case .applePay, .googlePay, .bit, .creditCard: return rawValue
        }
    }

    /// Localized label shown to the student in the payment-method chooser.
    var displayName: String {
        switch self {
        case .paypal:     return LocalizationSupport.localized("Pay with PayPal")
        case .applePay:   return LocalizationSupport.localized("Pay with Apple Pay")
        case .googlePay:  return LocalizationSupport.localized("Pay with Google Pay")
        case .bit:        return LocalizationSupport.localized("Pay with Bit")
        case .creditCard: return LocalizationSupport.localized("Pay with credit card")
        }
    }
}
