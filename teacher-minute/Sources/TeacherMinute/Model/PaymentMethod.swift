//
//  PaymentMethod.swift
//  teacher-minute
//
//  The checkout payment methods a student can choose from. Raw strings are the
//  wire format sent to the backend `createCheckoutSession` callable so it can
//  route the checkout to the matching provider. PayPal stays the default.
//

import Foundation

enum PaymentMethod: String, CaseIterable {
    case paypal
    case bit
    case creditCard = "credit_card"

    /// Localized label shown to the student in the payment-method chooser.
    var displayName: String {
        switch self {
        case .paypal:     return LocalizationSupport.localized("Pay with PayPal")
        case .bit:        return LocalizationSupport.localized("Pay with Bit")
        case .creditCard: return LocalizationSupport.localized("Pay with credit card")
        }
    }
}
