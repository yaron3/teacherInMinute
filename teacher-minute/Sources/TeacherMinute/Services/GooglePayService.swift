//
//  GooglePayService.swift
//  teacher-minute
//
//  Android counterpart to ApplePayService: presents the native Google Pay sheet
//  through Braintree and returns a payment method nonce for
//  `confirmGooglePayPayment`. PayPal's Orders v2 `google_pay` payment_source
//  cannot drive a native sheet — it silently degrades to a PayPal login page —
//  so Google Pay goes through Braintree exactly like Apple Pay does.
//

import Foundation

enum GooglePayServiceError: LocalizedError {
  case unsupported
  case cancelled
  case tokenizationFailed(String)

  var errorDescription: String? {
    switch self {
    case .unsupported: return "Google Pay is not available on this device."
    case .cancelled: return "Google Pay was cancelled."
    case .tokenizationFailed(let message): return message
    }
  }
}

#if os(Android)
import SkipBridge

struct GooglePayService {
  static let shared = GooglePayService()
  private init() {}

  /// Presents the Google Pay sheet. Returns a Braintree payment method nonce on
  /// success, to be submitted to `confirmGooglePayPayment`.
  func startPayment(
    clientToken: String,
    amountCents: Int,
    currency: String,
    merchantName: String,
    countryCode: String,
    environment: String
  ) async throws -> String {
    // Google Pay wants a decimal string ("20.00"), not minor units.
    let totalPrice = String(format: "%.2f", Double(amountCents) / 100)
    let result = try await Task.detached(priority: .userInitiated) {
      try AndroidGooglePayBridge.requestPayment(
        clientToken: clientToken,
        currencyCode: currency,
        totalPrice: totalPrice,
        merchantName: merchantName,
        countryCode: countryCode,
        environment: environment
      )
    }.value

    if result == "cancelled" {
      throw GooglePayServiceError.cancelled
    }
    let parts = result.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0] == "success", !parts[1].isEmpty else {
      throw GooglePayServiceError.tokenizationFailed("Google Pay returned no payment token.")
    }
    return String(parts[1])
  }
}

private enum AndroidGooglePayBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidGooglePayManager")
  private static let requestPaymentMethod = managerClass.getStaticMethodID(
    name: "requestPayment",
    sig: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"
  )!

  static func requestPayment(
    clientToken: String,
    currencyCode: String,
    totalPrice: String,
    merchantName: String,
    countryCode: String,
    environment: String
  ) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: requestPaymentMethod,
        options: [.kotlincompat],
        args: [
          clientToken.toJavaParameter(options: [.kotlincompat]),
          currencyCode.toJavaParameter(options: [.kotlincompat]),
          totalPrice.toJavaParameter(options: [.kotlincompat]),
          merchantName.toJavaParameter(options: [.kotlincompat]),
          countryCode.toJavaParameter(options: [.kotlincompat]),
          environment.toJavaParameter(options: [.kotlincompat])
        ]
      )
    }
  }
}
#endif
