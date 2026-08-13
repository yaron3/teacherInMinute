//
//  BraintreeCardService.swift
//  teacher-minute
//
//  Tokenizes a raw credit card against Braintree and returns a payment method
//  nonce for `confirmCardPayment` to charge.
//
//  This talks to Braintree's public GraphQL API over plain HTTPS rather than
//  going through BraintreeCard (the iOS SDK), because the SDK is iOS-only and
//  the card form has to work identically on Android through Skip. The request
//  it sends is the same one the SDK sends.
//
//  The card number never touches our own backend: the app posts it straight to
//  Braintree, and only the returned nonce is sent to Cloud Functions.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Card input

/// Raw card details as typed by the buyer. Digits are extracted from the
/// user-facing formatting (spaces, "MM/YY") by the validating initializer.
struct CardDetails {
  let number: String
  let expirationMonth: String
  let expirationYear: String
  let cvv: String
  let cardholderName: String
  let postalCode: String
}

// MARK: - Errors

enum BraintreeCardError: Error {
  /// The client token issued by the backend could not be decoded.
  case invalidClientToken
  /// Braintree rejected the card (bad number, expired, declined at tokenization).
  case tokenizationFailed(String)
  /// The tokenization request itself failed (offline, timeout, 5xx).
  case network(String)
}

extension BraintreeCardError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .invalidClientToken:
      return LocalizationSupport.localized("Could not start the card payment. Please try again.")
    case .tokenizationFailed(let message):
      return message
    case .network(let message):
      return message
    }
  }
}

// MARK: - Service

/// Deliberately not `@MainActor`: the tokenization request must run off the
/// main thread (Android throws `NetworkOnMainThreadException` otherwise).
enum BraintreeCardService {

  /// Braintree GraphQL API version this request is written against. Sent as the
  /// `Braintree-Version` header; the client token's own date is preferred when
  /// present so a token minted for a newer schema still validates.
  static let fallbackAPIVersion = "2018-05-10"

  /// Tokenizes `card` with the Braintree client token issued by
  /// `createCardCheckout`, returning a single-use payment method nonce.
  static func tokenize(card: CardDetails, clientToken: String) async throws -> String {
    let authorization = try ClientTokenPayload(clientToken: clientToken)

    var request = URLRequest(url: authorization.graphQLURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(authorization.authorizationFingerprint)", forHTTPHeaderField: "Authorization")
    request.setValue(authorization.apiVersion, forHTTPHeaderField: "Braintree-Version")
    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(for: card))

    let data: Data
    do {
      let (responseData, _) = try await URLSession.shared.data(for: request)
      data = responseData
    } catch {
      logger.error("[CardPayment] tokenization request failed error=\(error.localizedDescription)")
      throw BraintreeCardError.network(
        LocalizationSupport.localized("Could not reach the payment service. Check your connection and try again.")
      )
    }

    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      logger.error("[CardPayment] tokenization response was not JSON")
      throw BraintreeCardError.tokenizationFailed(Self.genericDeclineMessage)
    }

    // GraphQL reports card problems in `errors` with HTTP 200, so this has to be
    // checked before looking for a token.
    if let errors = json["errors"] as? [[String: Any]], !errors.isEmpty {
      let message = errors.compactMap { $0["message"] as? String }.first
      logger.error("[CardPayment] tokenization rejected message=\(message ?? "(none)")")
      throw BraintreeCardError.tokenizationFailed(message ?? Self.genericDeclineMessage)
    }

    guard
      let payload = json["data"] as? [String: Any],
      let tokenized = payload["tokenizeCreditCard"] as? [String: Any],
      let token = tokenized["token"] as? String,
      !token.isEmpty
    else {
      logger.error("[CardPayment] tokenization response missing token")
      throw BraintreeCardError.tokenizationFailed(Self.genericDeclineMessage)
    }

    logger.info("[CardPayment] card tokenized")
    return token
  }

  static var genericDeclineMessage: String {
    LocalizationSupport.localized("This card could not be processed. Please check the details or try another card.")
  }

  static func requestBody(for card: CardDetails) -> [String: Any] {
    var creditCard: [String: Any] = [
      "number": card.number,
      "expirationMonth": card.expirationMonth,
      "expirationYear": card.expirationYear,
      "cvv": card.cvv,
    ]
    if !card.cardholderName.isEmpty {
      creditCard["cardholderName"] = card.cardholderName
    }
    if !card.postalCode.isEmpty {
      creditCard["billingAddress"] = ["postalCode": card.postalCode]
    }
    return [
      "query": """
        mutation TokenizeCreditCard($input: TokenizeCreditCardInput!) {
          tokenizeCreditCard(input: $input) { token }
        }
        """,
      "variables": ["input": ["creditCard": creditCard]],
    ]
  }
}

// MARK: - Client token

/// The pieces of a Braintree client token the GraphQL call needs. A client
/// token is base64-encoded JSON (older gateways return the JSON directly), so
/// both encodings are accepted.
struct ClientTokenPayload {
  let authorizationFingerprint: String
  let graphQLURL: URL
  let apiVersion: String

  init(clientToken: String) throws {
    let trimmed = clientToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard
      let json = Self.decodeJSON(trimmed),
      let fingerprint = json["authorizationFingerprint"] as? String,
      !fingerprint.isEmpty
    else {
      logger.error("[CardPayment] client token could not be decoded")
      throw BraintreeCardError.invalidClientToken
    }

    let graphQL = json["graphQL"] as? [String: Any]
    let environment = (json["environment"] as? String) ?? "sandbox"
    let urlString = (graphQL?["url"] as? String) ?? Self.defaultGraphQLURL(environment: environment)

    guard let url = URL(string: urlString) else {
      logger.error("[CardPayment] client token has no usable GraphQL URL")
      throw BraintreeCardError.invalidClientToken
    }

    self.authorizationFingerprint = fingerprint
    self.graphQLURL = url
    self.apiVersion = (graphQL?["date"] as? String) ?? BraintreeCardService.fallbackAPIVersion
  }

  static func decodeJSON(_ clientToken: String) -> [String: Any]? {
    if let decoded = Data(base64Encoded: clientToken),
       let json = try? JSONSerialization.jsonObject(with: decoded) as? [String: Any] {
      return json
    }
    // Version 1 tokens are raw JSON rather than base64.
    if let json = try? JSONSerialization.jsonObject(with: Data(clientToken.utf8)) as? [String: Any] {
      return json
    }
    return nil
  }

  static func defaultGraphQLURL(environment: String) -> String {
    environment.lowercased() == "production"
      ? "https://payments.braintree-api.com/graphql"
      : "https://payments.sandbox.braintree-api.com/graphql"
  }
}
