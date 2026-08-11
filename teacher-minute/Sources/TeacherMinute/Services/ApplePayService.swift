//
//  ApplePayService.swift
//  teacher-minute
//

#if canImport(UIKit)
import UIKit
import PassKit
import BraintreeApplePay

/// Presents the native Apple Pay sheet and tokenizes the result through Braintree.
/// Braintree's `makePaymentRequest()` fills in `countryCode`/`currencyCode`/`merchantIdentifier`/
/// `supportedNetworks` from the Braintree Control Panel's Apple Pay configuration — the amount
/// (`paymentSummaryItems`) is the only piece we set ourselves, from the checkout the backend created.
@MainActor
final class ApplePayService: NSObject {
  static let shared = ApplePayService()
  private override init() {}

  enum ApplePayServiceError: LocalizedError {
    case unsupported
    case noPresentingViewController
    case cancelled
    case tokenizationFailed(String)

    var errorDescription: String? {
      switch self {
      case .unsupported: return "Apple Pay is not available on this device."
      case .noPresentingViewController: return "Cannot find a view controller to present Apple Pay."
      case .cancelled: return "Apple Pay was cancelled."
      case .tokenizationFailed(let message): return message
      }
    }
  }

  private var continuation: CheckedContinuation<String, Error>?
  private var applePayClient: BTApplePayClient?

  func canMakePayments() -> Bool {
    PKPaymentAuthorizationViewController.canMakePayments()
  }

  /// Presents the Apple Pay sheet. Returns a Braintree payment method nonce on success,
  /// to be submitted to `confirmApplePayPayment`.
  func startPayment(clientToken: String, amountCents: Int, label: String) async throws -> String {
    guard canMakePayments() else { throw ApplePayServiceError.unsupported }

    let client = BTApplePayClient(authorization: clientToken)
    applePayClient = client

    let paymentRequest = try await makePaymentRequest(using: client).value
    paymentRequest.paymentSummaryItems = [
      PKPaymentSummaryItem(label: label, amount: NSDecimalNumber(value: Double(amountCents) / 100))
    ]
    paymentRequest.merchantCapabilities = .capability3DS

    guard let authController = PKPaymentAuthorizationViewController(paymentRequest: paymentRequest) else {
      throw ApplePayServiceError.unsupported
    }
    authController.delegate = self

    guard let presenter = UIApplication.topMostViewController() else {
      throw ApplePayServiceError.noPresentingViewController
    }

    return try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      presenter.present(authController, animated: true)
    }
  }

  private struct UnsafeSendable<Value>: @unchecked Sendable {
    let value: Value
  }

  private func makePaymentRequest(using client: BTApplePayClient) async throws -> UnsafeSendable<PKPaymentRequest> {
    try await withCheckedThrowingContinuation { continuation in
      client.makePaymentRequest { paymentRequest, error in
        if let paymentRequest {
          continuation.resume(returning: UnsafeSendable(value: paymentRequest))
        } else {
          continuation.resume(
            throwing: error ?? ApplePayServiceError.tokenizationFailed("Could not create Apple Pay request")
          )
        }
      }
    }
  }

  private func finish(with result: Result<String, Error>) {
    guard let continuation else { return }
    self.continuation = nil
    continuation.resume(with: result)
  }
}

extension ApplePayService: @preconcurrency PKPaymentAuthorizationViewControllerDelegate {
  func paymentAuthorizationViewControllerDidFinish(_ controller: PKPaymentAuthorizationViewController) {
    controller.dismiss(animated: true)
    // A no-op if didAuthorizePayment already resolved the continuation on success/failure.
    finish(with: .failure(ApplePayServiceError.cancelled))
  }

  func paymentAuthorizationViewController(
    _ controller: PKPaymentAuthorizationViewController,
    didAuthorizePayment payment: PKPayment,
    handler completion: @escaping (PKPaymentAuthorizationResult) -> Void
  ) {
    guard let client = applePayClient else {
      completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
      finish(with: .failure(ApplePayServiceError.tokenizationFailed("Missing Apple Pay client")))
      return
    }
    client.tokenize(payment) { nonce, error in
      if let nonce {
        let nonceValue = nonce.nonce
        completion(PKPaymentAuthorizationResult(status: .success, errors: nil))
        Task { @MainActor in
          self.finish(with: .success(nonceValue))
        }
      } else {
        let message = error?.localizedDescription ?? "Apple Pay tokenization failed"
        completion(PKPaymentAuthorizationResult(status: .failure, errors: nil))
        Task { @MainActor in
          self.finish(with: .failure(ApplePayServiceError.tokenizationFailed(message)))
        }
      }
    }
  }
}
#endif
