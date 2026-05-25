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
  let connectionFeeCents: Int
}

struct QuestionStatusResult {
  let status: String
  let liveKitRoom: String?
  let liveKitToken: String?
  let questionId: String?
}

struct CheckoutSessionResult {
  let checkoutURL: URL
}

struct PaymentSettingsSessionResult {
  let settingsURL: URL
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
    guard
      let questionId = result["questionId"] as? String,
      let feeCents   = result["connectionFeeCents"] as? Int
    else { throw FunctionsError.decodingError() }
    return CreateQuestionResult(questionId: questionId, connectionFeeCents: feeCents)
  }

  func cancelQuestion(questionId: String) async throws {
    _ = try await call(function: "cancelQuestion", data: ["questionId": questionId])
  }

  func rateTeacher(questionId: String, teacherId: String, rating: Int) async throws {
    _ = try await call(
      function: "rateTeacher",
      data: [
        "questionId": questionId,
        "teacherId": teacherId,
        "rating": rating
      ]
    )
  }

  func getQuestionStatus(questionId: String) async throws -> QuestionStatusResult {
    let result = try await call(function: "getQuestionStatus", data: ["questionId": questionId])
    guard let status = result["status"] as? String else { throw FunctionsError.decodingError() }
    return QuestionStatusResult(
      status: status,
      liveKitRoom: result["liveKitRoom"] as? String,
      liveKitToken: result["liveKitToken"] as? String,
	  questionId: Self.firstString(in: result, keys: ["questionId", "questionID", "id"])
    )
  }

  func createCheckoutSession(pricingOptionID: String) async throws -> CheckoutSessionResult {
    let result = try await call(
      function: "createCheckoutSession",
      data: [
        "pricingOptionId": pricingOptionID,
        "pricingOptionID": pricingOptionID,
        "pricingOption": pricingOptionID,
        "packageId": pricingOptionID,
        "packageID": pricingOptionID
      ]
    )
    guard
      let urlString = Self.firstString(in: result, keys: ["checkoutUrl", "checkoutURL", "url"]),
      let checkoutURL = URL(string: urlString)
    else {
      logger.error("[PaymentReturn] createCheckoutSession missing checkout URL in result=\(result)")
      throw FunctionsError.decodingError(function: "createCheckoutSession", response: "\(result)")
    }
    return CheckoutSessionResult(checkoutURL: checkoutURL)
  }

  func createPaymentSettingsSession() async throws -> PaymentSettingsSessionResult {
    let result = try await call(function: "createPaymentSettingsSession", data: [:])
    guard
      let urlString = Self.firstString(in: result, keys: ["settingsUrl", "settingsURL", "portalUrl", "portalURL", "url"]),
      let settingsURL = URL(string: urlString)
    else { throw FunctionsError.decodingError() }
    return PaymentSettingsSessionResult(settingsURL: settingsURL)
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
    print("TeacherMinute FunctionsService calling \(name) data=\(data)")
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
    print("TeacherMinute FunctionsService received \(name) bytes=\(responseData.count) response=\(responseString)")
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
