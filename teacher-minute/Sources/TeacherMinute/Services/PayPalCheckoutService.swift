//
//  PayPalCheckoutService.swift
//  teacher-minute
//
// Approves a PayPal order with PayPal's native iOS SDK (paypal-ios 3.2.0's
// PayPalPayments, copied under Vendor/PayPalCheckout): the PayPal app when it
// is installed and the buyer is
// eligible, otherwise PayPal's page in an ASWebAuthenticationSession. It is the
// app's side of what the web does with PayPal's JS SDK — the backend creates
// the Orders v2 order (createCheckoutSession) and captures it once approved
// (capturePayPalOrder); this only gets the buyer's approval in between.
//
// The buyer comes back through a Universal Link on moreh-lerega.co.il (the
// Associated Domains entitlement, and the apple-app-site-association file that
// Firebase Hosting serves) or, failing that, the app's own URL scheme. Both
// reach `handleReturnURL` from the root `onOpenURL`. The same return and
// cancel links must be registered on the PayPal app in PayPal's dashboard.

#if canImport(UIKit)
import UIKit
import CorePayments
import PayPalPayments

@MainActor
final class PayPalCheckoutService {
  static let shared = PayPalCheckoutService()
  private init() {}

  enum Outcome {
    case approved
    case cancelled
  }

  /// The links PayPal sends the buyer back on.
  static let returnURL = URL(string: "https://moreh-lerega.co.il/paypal/return")!
  static let cancelURL = URL(string: "https://moreh-lerega.co.il/paypal/cancel")!
  private static let fallbackHost = "paypal-return"

  /// The client running the current checkout; kept so a return link that
  /// arrives later can be handed to it.
  private var client: PayPalClient?

  /// Starts PayPal's shopper session. The SDK requires it before `approve`,
  /// and suggests starting it while the order is being created so the two
  /// overlap.
  func prepare(_ config: PayPalSDKConfig) {
    let coreConfig = CoreConfig(
      clientID: config.clientID,
      environment: config.isLive ? .live : .sandbox,
      merchantID: config.merchantID
    )
    let client = PayPalClient(config: coreConfig)
    self.client = client
    client.createPayPalSession(
      sessionType: .checkout,
      urlConfig: PayPalURLConfig(
        returnAppURL: Self.returnURL,
        cancelAppURL: Self.cancelURL,
        fallbackSchemeURL: Self.fallbackSchemeURL
      ),
      userAction: .payNow
    )
  }

  /// Shows PayPal for the order and waits for the buyer. Throws when PayPal
  /// could not be shown or failed; a buyer backing out is `.cancelled`.
  func approve(orderID: String) async throws -> Outcome {
    guard let client else { throw PayPalCheckoutError.notPrepared }
    return try await withCheckedThrowingContinuation { continuation in
      client.start(orderID: orderID) { result in
        switch result {
        case .success:
          continuation.resume(returning: .approved)
        case .failure(let error) where PayPalError.isCheckoutCanceled(error):
          continuation.resume(returning: .cancelled)
        case .failure(let error):
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Hands PayPal's return link to the SDK, which finishes `approve`. Returns
  /// false for any other link, which the caller handles as before.
  func handleReturnURL(_ url: URL) -> Bool {
    guard Self.isPayPalReturn(url) else { return false }
    if let client {
      client.handleReturnURL(url)
    } else {
      logger.info("[PayPalCheckout] return link with no checkout in progress url=\(url.absoluteString)")
    }
    return true
  }

  private static func isPayPalReturn(_ url: URL) -> Bool {
    if url.host == returnURL.host, url.path.hasPrefix("/paypal/") { return true }
    if let scheme = appURLScheme, url.scheme == scheme, url.host == fallbackHost { return true }
    return false
  }

  /// `<app scheme>://paypal-return`, for a buyer whose Universal Link does not
  /// open the app.
  private static var fallbackSchemeURL: URL? {
    appURLScheme.flatMap { URL(string: "\($0)://\(fallbackHost)") }
  }

  private static var appURLScheme: String? {
    guard let scheme = Bundle.main.object(forInfoDictionaryKey: "TIMAppURLScheme") as? String,
          !scheme.isEmpty
    else { return nil }
    return scheme
  }
}

enum PayPalCheckoutError: LocalizedError {
  case notPrepared

  var errorDescription: String? {
    switch self {
    case .notPrepared: return "PayPal checkout was started before its session."
    }
  }
}
#endif
