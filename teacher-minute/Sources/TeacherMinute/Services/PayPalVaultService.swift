//
//  PayPalVaultService.swift
//  teacher-minute
//
// Runs Braintree's PayPal login so an account can be confirmed and vaulted —
// distinct from the plain, always-redirect PayPal checkout used elsewhere (see
// PaymentMethod.swift / paypal.ts on the backend).
//
// The two platforms reach the same result by different routes:
//   iOS     — `BTPayPalClient` presents its own `ASWebAuthenticationSession`,
//             so there is nothing else in the app to wire up.
//   Android — a browser switch back into the app via an App Link, handled by
//             AndroidPayPalManager (see also the assetlinks.json served from
//             Firebase Hosting and the intent-filter in AndroidManifest.xml).

#if canImport(UIKit)
import UIKit
import BraintreeCore
import BraintreePayPal

@MainActor
final class PayPalVaultService: NSObject {
  static let shared = PayPalVaultService()
  private override init() {}

  enum PayPalVaultServiceError: LocalizedError {
    case cancelled
    case tokenizationFailed(String)

    var errorDescription: String? {
      switch self {
      case .cancelled: return "Saving PayPal was cancelled."
      case .tokenizationFailed(let message): return message
      }
    }
  }

  /// Presents PayPal's login/consent flow and returns the resulting nonce, to
  /// be submitted to the `savePayPalVault` callable for vaulting.
  func vaultPayPalAccount(clientToken: String) async throws -> String {
    let client = BTPayPalClient(authorization: clientToken)
    let request = BTPayPalVaultRequest()
    do {
      let nonce = try await client.tokenize(request)
      return nonce.nonce
    } catch BTPayPalError.canceled {
      throw PayPalVaultServiceError.cancelled
    } catch let error as BTPayPalError {
      let message = Self.gatewayMessage(from: error)
      logger.error("[PayPalVault] tokenize failed: \(message)")
      throw PayPalVaultServiceError.tokenizationFailed(message)
    } catch {
      logger.error("[PayPalVault] tokenize failed: \(error.localizedDescription)")
      throw PayPalVaultServiceError.tokenizationFailed(error.localizedDescription)
    }
  }

  /// Braintree's own message for a failed *vault* flow is unreadable:
  /// BTPayPalClient takes its detail from `paymentResource.errorDetails.issue`,
  /// a key only the checkout flow returns, so a billing-agreement failure falls
  /// through to interpolating the whole response dictionary into the message —
  /// every header and no reason.
  ///
  /// The gateway's own explanation rides along in that dictionary, but it has
  /// to be read off the enum's payload: `BTPayPalError` conforms to
  /// `CustomNSError` without implementing `errorUserInfo`, so bridging it to
  /// `NSError` yields an empty `userInfo` and loses the body entirely.
  private static func gatewayMessage(from error: BTPayPalError) -> String {
    guard case .httpPostRequestError(let info) = error,
          let body = info[BTCoreConstants.jsonResponseBodyKey] as? BTJSON
    else {
      return error.localizedDescription
    }

    let reason = body["error"]["developer_message"].asString()
      ?? body["error"]["message"].asString()
      ?? body["agreementSetup"]["errorDetails"][0]["issue"].asString()
      ?? body["errors"][0]["message"].asString()

    if let reason, !reason.isEmpty {
      return reason
    }

    // An unfamiliar shape: show the body itself rather than the headers, so the
    // failure is still diagnosable from the console.
    if let raw = body.asDictionary() {
      return "\(raw)"
    }
    return error.localizedDescription
  }
}

#elseif os(Android)
import Foundation
import SkipBridge

@MainActor
final class PayPalVaultService {
  static let shared = PayPalVaultService()
  private init() {}

  enum PayPalVaultServiceError: LocalizedError {
    case cancelled
    case tokenizationFailed(String)

    var errorDescription: String? {
      switch self {
      case .cancelled: return "Saving PayPal was cancelled."
      case .tokenizationFailed(let message): return message
      }
    }
  }

  /// Opens PayPal in the browser and returns the resulting nonce once the
  /// buyer comes back. The Kotlin side blocks until the browser switch
  /// resolves, so it must run off the main thread.
  func vaultPayPalAccount(clientToken: String) async throws -> String {
    let result: String
    do {
      result = try await Task.detached(priority: .userInitiated) {
        try AndroidPayPalBridge.requestVaultNonce(clientToken: clientToken)
      }.value
    } catch {
      throw PayPalVaultServiceError.tokenizationFailed(error.localizedDescription)
    }

    if result == "cancelled" {
      throw PayPalVaultServiceError.cancelled
    }
    // Kotlin reports success as "success|<nonce>" so a nonce can never be
    // confused with the cancellation sentinel.
    guard result.hasPrefix("success|") else {
      throw PayPalVaultServiceError.tokenizationFailed("Unexpected PayPal result")
    }
    let nonce = String(result.dropFirst("success|".count))
    guard !nonce.isEmpty else {
      throw PayPalVaultServiceError.tokenizationFailed("PayPal returned an empty nonce")
    }
    return nonce
  }
}

private enum AndroidPayPalBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidPayPalManager")
  private static let requestVaultNonceMethod = managerClass.getStaticMethodID(
    name: "requestVaultNonce",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!

  static func requestVaultNonce(clientToken: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: requestVaultNonceMethod,
        options: [.kotlincompat],
        args: [clientToken.toJavaParameter(options: [.kotlincompat])]
      )
    }
  }
}
#endif
