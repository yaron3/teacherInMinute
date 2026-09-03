//
//  FunctionsService.swift
//  teacher-minute
//
// Calls Firebase Cloud Functions (callable) via raw HTTPS.
// Works on both iOS and Android through SkipFoundation's URLSession.
//
// Callable protocol:
//   POST https://{region}-{projectId}.cloudfunctions.net/{functionName}

//   Headers: Content-Type: application/json
//            Authorization: Bearer {firebaseIdToken}
//   Body:    { "data": { ... } }
//   Success: { "result": { ... } }
//   Error:   { "error": { "message": "...", "status": "..." } }

import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipBridge
import SkipFirebaseAuth
#endif

// MARK: - Errors

enum FunctionsError: Error {
  case notSignedIn
  case httpError(statusCode: Int)
  case serverError(message: String, status: String)
  case decodingError(function: String? = nil, response: String? = nil)
}

extension FunctionsError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .notSignedIn:
      "Not signed in"
    case .httpError(let statusCode):
      "HTTP error \(statusCode)"
    case .serverError(let message, let status):
      "\(status): \(message)"
    case .decodingError(let function, let response):
      "Could not decode \(function ?? "function") response. \(response ?? "")"
    }
  }
}

// MARK: - Call result

struct AcceptInviteResult {
  let liveKitRoom: String?
  let liveKitToken: String?
  let studentId: String?
  let questionId: String?
}

struct CreateQuestionResult {
  let questionId: String
}

struct QuestionStatusResult {
  let status: String
  let liveKitRoom: String?
  let liveKitToken: String?
  let questionId: String?
  let aiAnswer: String?
  let aiAnswered: Bool
}

struct CheckoutSessionResult {
  let checkoutURL: URL
}

struct ApplePayCheckoutSession {
  let checkoutId: String
  let clientToken: String
  let amountCents: Int
  let currency: String
  let label: String
}

struct GooglePayCheckoutSession {
  let checkoutId: String
  let clientToken: String
  let amountCents: Int
  let currency: String
  let label: String
  /// Google's wallet environment — "TEST" or "PRODUCTION", tracking the
  /// backend's Braintree environment.
  let environment: String
  let merchantName: String
  let countryCode: String
}

struct EmailValidationResult {
  /// Trimmed and lowercased by the backend — store this, not what was typed.
  let email: String
  let isValid: Bool
  /// Why it was rejected, ready to show. Nil when the address is usable.
  let message: String?
}

struct PaymentSettingsSessionResult {
  let settingsURL: URL
}

struct PayPalVaultClientTokenResult {
  let clientToken: String
}

struct RedeemCouponResult {
  let minutesAdded: Int
}

// MARK: - Teacher earnings

/// One 7-day span within a month, as aggregated by the `teacherEarningsSummary`
/// backend service. Labels are built client-side so they follow the app language.
struct EarningsWeek {
  let index: Int
  let startDay: Int
  let endDay: Int
  let earningsCents: Int
  let minutesCount: Int
  let lessonCount: Int
}

struct EarningsMonth {
  let id: String   // "yyyy-MM"
  let year: Int
  let month: Int   // 1-12
  let earningsCents: Int
  let minutesCount: Int
  let lessonCount: Int
  let isCurrentMonth: Bool
  let weeks: [EarningsWeek]
}

/// The pending payout: a month's earnings, paid on the 9th of the month after
/// it (March is paid on 9 April) — see functions/src/payoutSchedule.ts.
struct EarningsNextPayment {
  let amountCents: Int
  /// Payout day as "yyyy-MM-dd"; formatted for display by the view model.
  let payoutDate: String
  /// "yyyy-MM" of the earnings period this payout covers.
  let periodMonthId: String
}

struct TeacherEarningsSummaryResult {
  let currency: String
  let totalEarningsCents: Int
  let months: [EarningsMonth]
  let nextPayment: EarningsNextPayment?
  /// Where the payout is sent, or `nil` if the teacher has not set one up.
  let payoutMethod: TeacherPayoutMethod?
  /// Short, non-sensitive description of the destination — a bank account is
  /// already masked to its last 4 digits by the backend.
  let payoutMethodSummary: String
  /// The banks the backend accepts, for the payout form's picker.
  let banks: [PayoutBank]
  /// The teacher's profile phone, offered as the Bit number so they don't have
  /// to retype a number the app already holds.
  let profilePhone: String
}

// MARK: - Teacher ratings

/// A teacher's public reputation, as aggregated by the `teacherRatingSummary`
/// backend service. `ratingCount == 0` means nobody has rated this teacher yet,
/// which the screens render as "no rating" rather than as zero stars.
struct TeacherRatingSummary {
  let teacherId: String
  let averageRating: Double
  let ratingCount: Int

  var hasRating: Bool { ratingCount > 0 }

  static func empty(teacherId: String) -> TeacherRatingSummary {
    TeacherRatingSummary(teacherId: teacherId, averageRating: 0, ratingCount: 0)
  }
}

// MARK: - Service

@MainActor
final class FunctionsService {
  static let shared = FunctionsService()
  private init() {}

  private let baseURLKey = "baseURL"
  private let defaultBaseURL = "https://us-central1-teacher-in-a-moment.cloudfunctions.net"

  // MARK: - Student callables

  func createQuestion(topic: String, text: String, photoUrls: [String] = [], conversationType: String = "text") async throws -> CreateQuestionResult {
    let result = try await call(
      function: "createQuestion",
      data: ["topic": topic, "text": text, "photoUrls": photoUrls, "conversationType": conversationType]
    )
    guard let questionId = result["questionId"] as? String
    else { throw FunctionsError.decodingError() }
    return CreateQuestionResult(questionId: questionId)
  }

  func cancelQuestion(questionId: String) async throws {
    _ = try await call(function: "cancelQuestion", data: ["questionId": questionId])
  }

  /// `comment` is the student's optional written feedback. The backend trims it
  /// and stores it on the rating; the teacher later reads it without the
  /// student's identity attached.
  func rateTeacher(questionId: String, teacherId: String, rating: Int, comment: String = "") async throws {
    var data: [String: Any] = [
      "questionId": questionId,
      "teacherId": teacherId,
      "rating": rating
    ]
    let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      data["comment"] = trimmed
    }
    _ = try await call(function: "rateTeacher", data: data)
  }

  func getQuestionStatus(questionId: String) async throws -> QuestionStatusResult {
    let result = try await call(function: "getQuestionStatus", data: ["questionId": questionId])
    guard let status = result["status"] as? String else { throw FunctionsError.decodingError() }
    return QuestionStatusResult(
      status: status,
      liveKitRoom: result["liveKitRoom"] as? String,
      liveKitToken: result["liveKitToken"] as? String,
      questionId: Self.firstString(in: result, keys: ["questionId", "questionID", "id"]),
      aiAnswer: nil,
      aiAnswered: false
    )
  }

  func redeemCoupon(couponCode: String) async throws -> RedeemCouponResult {
    let result = try await call(function: "redeemCoupon", data: ["couponCode": couponCode])
    guard let minutes = result["minutesAdded"] as? Int else {
      throw FunctionsError.decodingError(function: "redeemCoupon")
    }
    return RedeemCouponResult(minutesAdded: minutes)
  }

  func createCheckoutSession(pricingOptionID: String, paymentMethod: PaymentMethod = .paypal) async throws -> CheckoutSessionResult {
    var data: [String: Any] = [
      "pricingOptionId": pricingOptionID,
      "platform": Self.platformIdentifier
    ]
    // Keep this payload aligned with the backend callable schema. Sending legacy
    // aliases like `packageId`/`pricingOptionID` can fail strict validation with
    // INVALID_ARGUMENT before the function reaches the payment-provider code.
    if let wallet = paymentMethod.walletParameter {
      data["paymentMethod"] = wallet
    }
    let result = try await call(function: "createCheckoutSession", data: data)
    guard
      let urlString = Self.firstString(in: result, keys: ["checkoutUrl", "checkoutURL", "url"]),
      let checkoutURL = URL(string: urlString)
    else {
      logger.error("[PaymentReturn] createCheckoutSession missing checkout URL in result=\(result)")
      throw FunctionsError.decodingError(function: "createCheckoutSession", response: "\(result)")
    }
    return CheckoutSessionResult(checkoutURL: checkoutURL)
  }

  func createApplePayCheckout(pricingOptionID: String) async throws -> ApplePayCheckoutSession {
    let result = try await call(function: "createApplePayCheckout", data: ["pricingOptionId": pricingOptionID])
    guard
      let checkoutId = Self.firstString(in: result, keys: ["checkoutId", "checkoutID"]),
      let clientToken = result["clientToken"] as? String,
      let amountCents = result["amountCents"] as? Int,
      let currency = result["currency"] as? String
    else {
      logger.error("[PaymentReturn] createApplePayCheckout missing fields result=\(result)")
      throw FunctionsError.decodingError(function: "createApplePayCheckout", response: "\(result)")
    }
    let label = result["label"] as? String ?? "TeacherMinute"
    return ApplePayCheckoutSession(
      checkoutId: checkoutId,
      clientToken: clientToken,
      amountCents: amountCents,
      currency: currency,
      label: label
    )
  }

  func confirmApplePayPayment(checkoutId: String, nonce: String) async throws {
    _ = try await call(function: "confirmApplePayPayment", data: ["checkoutId": checkoutId, "nonce": nonce])
  }

  func createGooglePayCheckout(pricingOptionID: String) async throws -> GooglePayCheckoutSession {
    let result = try await call(function: "createGooglePayCheckout", data: ["pricingOptionId": pricingOptionID])
    guard
      let checkoutId = Self.firstString(in: result, keys: ["checkoutId", "checkoutID"]),
      let clientToken = result["clientToken"] as? String,
      let amountCents = result["amountCents"] as? Int,
      let currency = result["currency"] as? String
    else {
      logger.error("[PaymentReturn] createGooglePayCheckout missing fields result=\(result)")
      throw FunctionsError.decodingError(function: "createGooglePayCheckout", response: "\(result)")
    }
    return GooglePayCheckoutSession(
      checkoutId: checkoutId,
      clientToken: clientToken,
      amountCents: amountCents,
      currency: currency,
      label: result["label"] as? String ?? "TeacherMinute",
      environment: result["environment"] as? String ?? "TEST",
      merchantName: result["merchantName"] as? String ?? "TeacherMinute",
      countryCode: result["countryCode"] as? String ?? "US"
    )
  }

  func confirmGooglePayPayment(checkoutId: String, nonce: String) async throws {
    _ = try await call(function: "confirmGooglePayPayment", data: ["checkoutId": checkoutId, "nonce": nonce])
  }

  func createPaymentSettingsSession() async throws -> PaymentSettingsSessionResult {
    let result = try await call(function: "createPaymentSettingsSession", data: [:])
    guard
      let urlString = Self.firstString(in: result, keys: ["settingsUrl", "settingsURL", "portalUrl", "portalURL", "url"]),
      let settingsURL = URL(string: urlString)
    else { throw FunctionsError.decodingError() }
    return PaymentSettingsSessionResult(settingsURL: settingsURL)
  }

  // MARK: - Saved PayPal (Braintree vault)

  func createPayPalVaultClientToken() async throws -> PayPalVaultClientTokenResult {
    let result = try await call(function: "createPayPalVaultClientToken", data: [:])
    guard let clientToken = result["clientToken"] as? String else {
      throw FunctionsError.decodingError(function: "createPayPalVaultClientToken", response: "\(result)")
    }
    return PayPalVaultClientTokenResult(clientToken: clientToken)
  }

  /// Vaults the PayPal account behind `nonce` and returns its (masked) email
  /// for display.
  func savePayPalVault(nonce: String) async throws -> String {
    let result = try await call(function: "savePayPalVault", data: ["nonce": nonce])
    return result["email"] as? String ?? ""
  }

  func removeSavedPayPal() async throws {
    _ = try await call(function: "removeSavedPayPal", data: [:])
  }

  /// Charges the student's previously saved PayPal account directly — no
  /// PayPal login, no checkout URL.
  func chargeSavedPayPal(pricingOptionID: String) async throws {
    _ = try await call(function: "chargeSavedPayPal", data: ["pricingOptionId": pricingOptionID])
  }

  // MARK: - Teacher ratings

  /// Star average and review count for the given teachers. Teacher documents
  /// are not readable cross-user, so this is the only way a student can see a
  /// teacher's rating.
  func teacherRatingSummaries(teacherIds: [String]) async throws -> [TeacherRatingSummary] {
    var data: [String: Any] = [:]
    if !teacherIds.isEmpty {
      data["teacherIds"] = teacherIds
    }
    let result = try await call(function: "teacherRatingSummary", data: data)
    let rows = result["ratings"] as? [[String: Any]] ?? []
    return rows.compactMap { row in
      guard let teacherId = row["teacherId"] as? String else { return nil }
      return TeacherRatingSummary(
        teacherId: teacherId,
        averageRating: Self.doubleValue(row["averageRating"]) ?? 0,
        ratingCount: Self.intValue(row["ratingCount"]) ?? 0
      )
    }
  }

  /// One teacher's rating, or the signed-in teacher's own when `teacherId` is
  /// `nil`. Returns an empty summary rather than throwing when nobody has rated
  /// them yet.
  func teacherRatingSummary(teacherId: String? = nil) async throws -> TeacherRatingSummary {
    let requested = teacherId.map { [$0] } ?? []
    let summaries = try await teacherRatingSummaries(teacherIds: requested)
    if let teacherId {
      return summaries.first(where: { $0.teacherId == teacherId }) ?? .empty(teacherId: teacherId)
    }
    return summaries.first ?? .empty(teacherId: "")
  }

  // MARK: - Teacher earnings

  /// Server-side aggregation of the teacher's completed lessons into monthly
  /// and weekly earnings, plus the pending payout. Replaces the client-side
  /// per-question fetch, which could not see months beyond its page limit.
  func teacherEarningsSummary() async throws -> TeacherEarningsSummaryResult {
    let result = try await call(function: "teacherEarningsSummary", data: [:])

    let monthRows = result["months"] as? [[String: Any]] ?? []
    let months: [EarningsMonth] = monthRows.compactMap { row in
      guard
        let id = row["id"] as? String,
        let year = Self.intValue(row["year"]),
        let month = Self.intValue(row["month"])
      else { return nil }

      let weekRows = row["weeks"] as? [[String: Any]] ?? []
      let weeks: [EarningsWeek] = weekRows.compactMap { weekRow in
        guard
          let index = Self.intValue(weekRow["index"]),
          let startDay = Self.intValue(weekRow["startDay"]),
          let endDay = Self.intValue(weekRow["endDay"])
        else { return nil }
        return EarningsWeek(
          index: index,
          startDay: startDay,
          endDay: endDay,
          earningsCents: Self.intValue(weekRow["earningsCents"]) ?? 0,
          minutesCount: Self.intValue(weekRow["minutesCount"]) ?? 0,
          lessonCount: Self.intValue(weekRow["lessonCount"]) ?? 0
        )
      }

      return EarningsMonth(
        id: id,
        year: year,
        month: month,
        earningsCents: Self.intValue(row["earningsCents"]) ?? 0,
        minutesCount: Self.intValue(row["minutesCount"]) ?? 0,
        lessonCount: Self.intValue(row["lessonCount"]) ?? 0,
        isCurrentMonth: row["isCurrentMonth"] as? Bool ?? false,
        weeks: weeks
      )
    }

    var nextPayment: EarningsNextPayment?
    if let payment = result["nextPayment"] as? [String: Any],
       let payoutDate = payment["payoutDate"] as? String {
      nextPayment = EarningsNextPayment(
        amountCents: Self.intValue(payment["amountCents"]) ?? 0,
        payoutDate: payoutDate,
        periodMonthId: payment["periodMonthId"] as? String ?? ""
      )
    }

    var payoutMethod: TeacherPayoutMethod?
    if let methodRow = result["payoutMethod"] as? [String: Any] {
      payoutMethod = TeacherPayoutMethod(data: methodRow)
    }

    let bankRows = result["banks"] as? [[String: Any]] ?? []
    let banks: [PayoutBank] = bankRows.compactMap { row in
      guard let code = row["code"] as? String, let name = row["name"] as? String else { return nil }
      return PayoutBank(code: code, name: name, nameHe: row["nameHe"] as? String ?? name)
    }

    return TeacherEarningsSummaryResult(
      currency: result["currency"] as? String ?? LessonFormatting.defaultCurrencyCode,
      totalEarningsCents: Self.intValue(result["totalEarningsCents"]) ?? 0,
      months: months,
      nextPayment: nextPayment,
      payoutMethod: payoutMethod,
      payoutMethodSummary: result["payoutMethodSummary"] as? String ?? "",
      banks: banks,
      profilePhone: result["profilePhone"] as? String ?? ""
    )
  }

  /// Confirms a PayPal payout account from a nonce produced by the teacher
  /// completing a PayPal login, and saves it. Returns the confirmed email and
  /// its masked summary — PayPal has no address-lookup API, so completing the
  /// login is the only way to know the account exists.
  func verifyPayPalPayoutAccount(nonce: String) async throws -> (email: String, summary: String) {
    let result = try await call(function: "verifyPayPalPayoutAccount", data: ["nonce": nonce])
    let method = result["payoutMethod"] as? [String: Any] ?? [:]
    return (
      email: method["email"] as? String ?? "",
      summary: result["payoutMethodSummary"] as? String ?? ""
    )
  }

  /// Saves where the teacher's payout is sent. The backend validates the fields
  /// the chosen type requires and throws `invalid-argument` with a message the
  /// teacher can act on. Returns the masked destination summary.
  /// Checks an address before it is submitted anywhere — the payout form
  /// today, email signup next. Stores nothing and needs no sign-in.
  ///
  /// `valid == false` carries a `message` explaining which check failed
  /// (malformed, or a domain that accepts no mail). Mailbox existence is only
  /// reported when the backend has a verification provider configured; when it
  /// does not, a well-formed address on a real mail domain reads as valid.
  func validateEmailAddress(_ email: String) async throws -> EmailValidationResult {
    let result = try await call(function: "validateEmailAddress", data: ["email": email])
    return EmailValidationResult(
      email: result["email"] as? String ?? email,
      isValid: result["valid"] as? Bool ?? false,
      message: result["message"] as? String
    )
  }

  func updateTeacherPayoutMethod(_ method: TeacherPayoutMethod) async throws -> String {
    let result = try await call(
      function: "updateTeacherPayoutMethod",
      data: ["payoutMethod": method.requestPayload]
    )
    return result["payoutMethodSummary"] as? String ?? ""
  }

  // MARK: - Teacher callables

  func acceptInvite(questionId: String) async throws -> AcceptInviteResult {
    let result = try await call(function: "acceptInvite", data: ["questionId": questionId, "inviteId": questionId])
	logger.info("acceptInvite result: \(result)")
    let suid = result["studentId"] as? String
      ?? result["studentUID"] as? String
      ?? result["studentId"] as? String
    let room = result["liveKitRoom"] as? String
    let token = result["liveKitToken"] as? String
    let questionId = Self.firstString(in: result, keys: ["questionId", "questionID", "id"])
    return AcceptInviteResult(liveKitRoom: room, liveKitToken: token, studentId: suid, questionId: questionId)
  }

  func declineInvite(questionId: String) async throws {
    _ = try await call(function: "declineInvite", data: ["questionId": questionId])
  }

  func startLesson(questionId: String) async throws -> String {
    let result = try await call(function: "startLesson", data: ["questionId": questionId])
    guard let questionId = result["questionId"] as? String else { throw FunctionsError.decodingError() }
    return questionId
  }

  func endLesson(questionId: String) async throws {
    _ = try await call(function: "endLesson", data: ["questionId": questionId])
  }

  // MARK: - Core HTTP caller

  private func call(function name: String, data: [String: Any]) async throws -> [String: Any] {
    let responseData: Data
    let statusCode: Int?
    let baseURL = await functionsBaseURL()

#if os(Android)
    logger.info("TeacherMinute FunctionsService calling \(name) data=\(data)")
    let payloadData = try JSONSerialization.data(withJSONObject: ["data": data])
    guard let payload = String(data: payloadData, encoding: .utf8) else {
      throw FunctionsError.decodingError()
    }
    let responseString = try await Task.detached(priority: .userInitiated) {
      try AndroidFunctionsBridge.callFunction(
        baseURL: baseURL,
        name: name,
        payloadJSON: payload
      )
    }.value
    responseData = Data(responseString.utf8)
    statusCode = nil
    logger.info("TeacherMinute FunctionsService received \(name) bytes=\(responseData.count) response=\(responseString)")
#else
    guard let url = URL(string: "\(baseURL)/\(name)") else {
      throw FunctionsError.decodingError()
    }

    let idToken = try await currentUserIdToken()

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: ["data": data])

    let (data, httpResponse) = try await URLSession.shared.data(for: request)
    responseData = data
    statusCode = (httpResponse as? HTTPURLResponse)?.statusCode
#endif

    if let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
       let error = json["error"] as? [String: Any] {
      let message = error["message"] as? String ?? "Unknown error"
      let status  = error["status"]  as? String ?? "UNKNOWN"
      logger.error("[FunctionsService] \(name) server error status=\(status) message=\(message)")
      throw FunctionsError.serverError(message: message, status: status)
    }

    if let statusCode, statusCode != 200 {
      throw FunctionsError.httpError(statusCode: statusCode)
    }

    guard
      let json   = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
      let result = json["result"] as? [String: Any]
    else {
      let responseText = String(data: responseData, encoding: .utf8)
      logger.error("[FunctionsService] \(name) decode failed response=\(responseText ?? "<non-utf8>")")
      throw FunctionsError.decodingError(function: name, response: responseText)
    }

    logger.info("[FunctionsService] \(name) result=\(result)")
    return result
  }

  private func functionsBaseURL() async -> String {
    await RemoteConfigService.shared.ready()
    return RemoteConfigService.shared.getURL(baseURLKey)?.absoluteString ?? defaultBaseURL
  }

  /// Platform tag sent to the backend so it can validate platform-specific
  /// wallets (e.g. Apple Pay is rejected on Android).
  private static var platformIdentifier: String {
#if os(Android)
    "android"
#else
    "ios"
#endif
  }

  /// JSON numbers arrive as `Int`, `Double` or `NSNumber` depending on platform
  /// and magnitude, so every numeric field is read through this.
  private static func intValue(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? Double { return Int(value) }
    if let value = value as? String { return Int(value) }
    return nil
  }

  /// Same story as `intValue`, for fields that carry a fraction (a star
  /// average, for instance).
  private static func doubleValue(_ value: Any?) -> Double? {
    if let value = value as? Double { return value }
    if let value = value as? Int { return Double(value) }
    if let value = value as? String { return Double(value) }
    return nil
  }

  private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
    for key in keys {
      if let value = dict[key] as? String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
      }
    }
    return nil
  }

#if !os(Android)
  // MARK: - Auth token

  private func currentUserIdToken() async throws -> String {
    guard let user = Auth.auth().currentUser else { throw FunctionsError.notSignedIn }
    return try await withCheckedThrowingContinuation { cont in
      user.getIDToken { token, error in
        if let error { cont.resume(throwing: error); return }
        cont.resume(returning: token ?? "")
      }
    }
  }
#endif
}

#if os(Android)
private enum AndroidFunctionsBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidFunctionsManager")
  private static let callFunctionMethod = managerClass.getStaticMethodID(
    name: "callFunction",
    sig: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;"
  )!

  static func callFunction(baseURL: String, name: String, payloadJSON: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: callFunctionMethod,
        options: [.kotlincompat],
        args: [
          baseURL.toJavaParameter(options: [.kotlincompat]),
          name.toJavaParameter(options: [.kotlincompat]),
          payloadJSON.toJavaParameter(options: [.kotlincompat]),
        ]
      )
    }
  }
}
#endif
