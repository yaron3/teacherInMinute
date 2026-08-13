import Foundation
import Testing
@testable import TeacherMinute

struct BraintreeCardServiceTests {

  static let card = CardDetails(
    number: "4111111111111111",
    expirationMonth: "07",
    expirationYear: "2030",
    cvv: "123",
    cardholderName: "Ada Lovelace",
    postalCode: ""
  )

  static func clientToken(_ payload: [String: Any]) -> String {
    let data = try! JSONSerialization.data(withJSONObject: payload)
    return data.base64EncodedString()
  }

  // MARK: - Client token

  @Test func readsFingerprintAndGraphQLURLFromTheClientToken() throws {
    let token = Self.clientToken([
      "version": 3,
      "authorizationFingerprint": "fingerprint-abc",
      "environment": "sandbox",
      "graphQL": ["url": "https://payments.sandbox.braintree-api.com/graphql", "date": "2018-05-08"],
    ])

    let payload = try ClientTokenPayload(clientToken: token)
    #expect(payload.authorizationFingerprint == "fingerprint-abc")
    #expect(payload.graphQLURL.absoluteString == "https://payments.sandbox.braintree-api.com/graphql")
    #expect(payload.apiVersion == "2018-05-08")
  }

  @Test func fallsBackToTheEnvironmentsGraphQLURL() throws {
    let production = try ClientTokenPayload(
      clientToken: Self.clientToken(["authorizationFingerprint": "f", "environment": "production"])
    )
    #expect(production.graphQLURL.absoluteString == "https://payments.braintree-api.com/graphql")
    #expect(production.apiVersion == BraintreeCardService.fallbackAPIVersion)

    let sandbox = try ClientTokenPayload(
      clientToken: Self.clientToken(["authorizationFingerprint": "f", "environment": "sandbox"])
    )
    #expect(sandbox.graphQLURL.absoluteString == "https://payments.sandbox.braintree-api.com/graphql")
  }

  @Test func acceptsAnUnencodedJSONClientToken() throws {
    let json = #"{"authorizationFingerprint":"raw-json","environment":"sandbox"}"#
    let payload = try ClientTokenPayload(clientToken: json)
    #expect(payload.authorizationFingerprint == "raw-json")
  }

  @Test func rejectsATokenWithoutAFingerprint() {
    #expect(throws: BraintreeCardError.self) {
      _ = try ClientTokenPayload(clientToken: Self.clientToken(["environment": "sandbox"]))
    }
    #expect(throws: BraintreeCardError.self) {
      _ = try ClientTokenPayload(clientToken: "not-a-token")
    }
  }

  // MARK: - Request body

  @Test func buildsTheTokenizeCreditCardMutation() throws {
    let body = BraintreeCardService.requestBody(for: Self.card)
    let query = try #require(body["query"] as? String)
    #expect(query.contains("tokenizeCreditCard"))

    let variables = try #require(body["variables"] as? [String: Any])
    let input = try #require(variables["input"] as? [String: Any])
    let creditCard = try #require(input["creditCard"] as? [String: Any])
    #expect(creditCard["number"] as? String == "4111111111111111")
    #expect(creditCard["expirationMonth"] as? String == "07")
    #expect(creditCard["expirationYear"] as? String == "2030")
    #expect(creditCard["cvv"] as? String == "123")
    #expect(creditCard["cardholderName"] as? String == "Ada Lovelace")
    // An empty postal code must not be sent — Braintree AVS treats a blank
    // billing address as a mismatch rather than as "not provided".
    #expect(creditCard["billingAddress"] == nil)
  }

  @Test func includesThePostalCodeWhenOneWasEntered() throws {
    let card = CardDetails(
      number: "4111111111111111",
      expirationMonth: "07",
      expirationYear: "2030",
      cvv: "123",
      cardholderName: "",
      postalCode: "94107"
    )
    let body = BraintreeCardService.requestBody(for: card)
    let variables = try #require(body["variables"] as? [String: Any])
    let input = try #require(variables["input"] as? [String: Any])
    let creditCard = try #require(input["creditCard"] as? [String: Any])
    let billing = try #require(creditCard["billingAddress"] as? [String: Any])
    #expect(billing["postalCode"] as? String == "94107")
    #expect(creditCard["cardholderName"] == nil)
  }

  @Test func theBodySerializesToJSON() throws {
    let body = BraintreeCardService.requestBody(for: Self.card)
    #expect(JSONSerialization.isValidJSONObject(body))
    _ = try JSONSerialization.data(withJSONObject: body)
  }
}
