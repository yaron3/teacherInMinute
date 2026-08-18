//
//  DemoStudentService.swift
//  teacher-minute
//
//  Lets a teacher simulate an incoming student question during a demo.
//  The request is written to RTDB (`demoStudent/requests/{id}`) and picked up by
//  the local `backend/demo-student` service, which writes the question text with
//  a local AI model (Qwen via Ollama) and invites this teacher to it.
//

import Foundation

#if !os(Android)
import FirebaseAuth
import FirebaseDatabase
#else
import SkipBridge
import SkipFirebaseAuth
#endif

// MARK: - Model

/// What the teacher asked the simulated student to ask about.
struct DemoStudentSimulation: Equatable {
  var topic: String = DemoStudentSimulation.topics[0]
  var difficulty: String = DemoStudentSimulation.difficulties[1]
  var conversationType: String = "text"
  var hint: String = ""

  /// Matches the topics accepted by `createQuestion` on the backend.
  static let topics = ["algebra", "geometry", "trigonometry", "calculus", "statistics", "arithmetic"]
  static let difficulties = ["easy", "medium", "hard"]
  static let conversationTypes = ["text", "audio", "video"]
}

/// Progress of one simulation request, as written back by the demo-student service.
struct DemoStudentRequestStatus: Equatable {
  let status: String            // pending | generating | dispatched | failed
  let questionId: String
  let questionText: String
  let source: String            // "llm" when the local model wrote it, "fallback" otherwise
  let error: String

  var isDispatched: Bool { status == "dispatched" }
  var isFailed: Bool { status == "failed" }
  var isTerminal: Bool { isDispatched || isFailed }
}

enum DemoStudentError: Error, LocalizedError {
  case notSignedIn
  case serviceOffline
  case notDelivered
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .notSignedIn:
      return LocalizationSupport.localized("Sign in as a teacher to simulate a question.")
    case .serviceOffline:
      return LocalizationSupport.localized("The demo student service is not running. Start it with `npm run dev` in backend/demo-student.")
    case .notDelivered:
      return LocalizationSupport.localized("The demo student service did not respond. Make sure it is running on your machine.")
    case .failed(let message):
      return message.isEmpty
        ? LocalizationSupport.localized("The demo student service could not create the question.")
        : message
    }
  }
}

// MARK: - Service

enum DemoStudentService {
  private static let requestsPath = "demoStudent/requests"
  private static let pollIntervalNanoseconds: UInt64 = 1_500_000_000
  private static let pollAttempts = 40   // ~60 s, covering a slow first token on a cold model

  /// Demo tooling stays out of release builds unless it is switched on remotely.
  @MainActor
  static var isEnabled: Bool {
#if DEBUG
    return true
#else
    return RemoteConfigService.shared.getBool("demo_student_enabled")
#endif
  }

  /// True when the local demo-student service has published presence. Returns
  /// true if presence cannot be read at all, so a stale rules deploy never
  /// blocks a demo — the request path still reports what happened.
  static func isServiceRunning() async -> Bool {
#if os(Android)
    guard let json = try? await Task.detached(priority: .userInitiated, operation: {
      try AndroidDemoStudentBridge.fetchServiceStatus()
    }).value else {
      return true
    }
    let status = json.trimmingCharacters(in: .whitespacesAndNewlines)
    return status.isEmpty || status == "online"
#else
    let ref = FirebaseDatabase.Database.database().reference(withPath: "demoStudent/service/status")
    let status: String? = await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
      ref.observeSingleEvent(of: .value) { snapshot in
        cont.resume(returning: snapshot.value as? String)
      } withCancel: { _ in
        cont.resume(returning: nil)
      }
    }
    guard let status else { return true }
    return status == "online"
#endif
  }

  /// Writes the simulation request and returns its id.
  static func submit(_ simulation: DemoStudentSimulation, teacherName: String) async throws -> String {
    guard let uid = Auth.auth().currentUser?.uid, !uid.isEmpty else {
      throw DemoStudentError.notSignedIn
    }

    let hint = simulation.hint.trimmingCharacters(in: .whitespacesAndNewlines)
    let payload: [String: Any] = [
      "teacherUid": uid,
      "teacherName": teacherName,
      "topic": simulation.topic,
      "difficulty": simulation.difficulty,
      "conversationType": simulation.conversationType,
      "language": LocalizationSupport.currentLanguageCode,
      "hint": String(hint.prefix(200)),
      "status": "pending",
      "createdAt": Date().timeIntervalSince1970 * 1000.0
    ]

    logger.info("[DemoStudent] submitting simulation topic=\(simulation.topic) difficulty=\(simulation.difficulty) type=\(simulation.conversationType)")

#if os(Android)
    let json = try JSONSerialization.data(withJSONObject: payload)
    let requestId = try await Task.detached(priority: .userInitiated) {
      try AndroidDemoStudentBridge.submitRequest(json: String(data: json, encoding: .utf8) ?? "{}")
    }.value
    guard !requestId.isEmpty else { throw DemoStudentError.notDelivered }
    return requestId
#else
    let ref = FirebaseDatabase.Database.database().reference(withPath: requestsPath).childByAutoId()
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      ref.setValue(payload) { error, _ in
        if let error {
          cont.resume(throwing: error)
        } else {
          cont.resume(returning: ())
        }
      }
    }
    return ref.key ?? ""
#endif
  }

  /// Reads the current state of a simulation request.
  static func fetchStatus(requestId: String) async throws -> DemoStudentRequestStatus? {
    guard !requestId.isEmpty else { return nil }

#if os(Android)
    let json = try await Task.detached(priority: .userInitiated) {
      try AndroidDemoStudentBridge.fetchStatus(requestId: requestId)
    }.value
    guard let data = json.data(using: .utf8),
          let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          !dict.isEmpty else {
      return nil
    }
    return status(from: dict)
#else
    let ref = FirebaseDatabase.Database.database().reference(withPath: "\(requestsPath)/\(requestId)")
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<DemoStudentRequestStatus?, Error>) in
      ref.observeSingleEvent(of: .value) { snapshot in
        guard let dict = snapshot.value as? [String: Any] else {
          cont.resume(returning: nil)
          return
        }
        cont.resume(returning: status(from: dict))
      } withCancel: { error in
        cont.resume(throwing: error)
      }
    }
#endif
  }

  /// Polls until the service reports the question was dispatched, or throws.
  static func awaitDispatch(requestId: String) async throws -> DemoStudentRequestStatus {
    for _ in 0..<pollAttempts {
      try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
      try Task.checkCancellation()

      guard let status = try? await fetchStatus(requestId: requestId) else { continue }
      if status.isFailed {
        logger.error("[DemoStudent] simulation failed — \(status.error)")
        throw DemoStudentError.failed(status.error)
      }
      if status.isDispatched {
        logger.info("[DemoStudent] simulation dispatched qid=\(status.questionId) source=\(status.source)")
        return status
      }
    }

    logger.error("[DemoStudent] simulation timed out requestId=\(requestId)")
    throw DemoStudentError.notDelivered
  }

  private static func status(from dict: [String: Any]) -> DemoStudentRequestStatus {
    DemoStudentRequestStatus(
      status: (dict["status"] as? String) ?? "pending",
      questionId: (dict["questionId"] as? String) ?? "",
      questionText: (dict["questionText"] as? String) ?? "",
      source: (dict["source"] as? String) ?? "",
      error: (dict["error"] as? String) ?? ""
    )
  }
}

// MARK: - Android bridge

#if os(Android)
private enum AndroidDemoStudentBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidDemoStudentManager")
  private static let submitMethod = managerClass.getStaticMethodID(
    name: "submitRequestJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!
  private static let statusMethod = managerClass.getStaticMethodID(
    name: "fetchRequestStatusJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!
  private static let serviceStatusMethod = managerClass.getStaticMethodID(
    name: "fetchServiceStatus",
    sig: "()Ljava/lang/String;"
  )!

  static func submitRequest(json: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: submitMethod,
        options: [.kotlincompat],
        args: [json.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }

  static func fetchServiceStatus() throws -> String {
    try jniContext {
      try managerClass.callStatic(method: serviceStatusMethod, options: [.kotlincompat], args: [])
    } as String
  }

  static func fetchStatus(requestId: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: statusMethod,
        options: [.kotlincompat],
        args: [requestId.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }
}
#endif
