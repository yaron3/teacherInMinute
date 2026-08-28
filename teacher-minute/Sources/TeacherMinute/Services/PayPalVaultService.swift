//
//  PayPalVaultService.swift
//  teacher-minute
//
// Vaults the buyer's PayPal account via Braintree so a later purchase can be
// charged with no PayPal login — distinct from the plain, always-redirect
// PayPal checkout used elsewhere (see PaymentMethod.swift / paypal.ts on the
// backend). `BTPayPalClient`'s standard (non app-switch) flow presents its own
// `ASWebAuthenticationSession` internally, so there is nothing else in the app
// to wire up (no URL scheme, no `onOpenURL`).

#if canImport(UIKit)
import UIKit
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
    } catch {
      throw PayPalVaultServiceError.tokenizationFailed(error.localizedDescription)
    }
  }
}
#endif
