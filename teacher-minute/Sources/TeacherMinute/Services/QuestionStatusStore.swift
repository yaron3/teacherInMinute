import Foundation

#if os(Android)
import SkipBridge
#else
import FirebaseDatabase
#endif

/// What the live listener currently knows about a question.
enum LiveQuestionStatus {
  /// A snapshot has arrived.
  case ready(QuestionStatusResult)
  /// The node exists no longer — the backend deletes it once a question is
  /// cancelled or archived, so this means "resolved, ask the server how".
  case gone
  /// Attached, but nothing delivered yet.
  case pending
  /// The listener was cancelled; fall back to the callable.
  case failed
}

@MainActor
enum QuestionStatusStore {

  // MARK: - Live listener
  //
  // A student waiting for a teacher used to call getQuestionStatus once a
  // second: a Cloud Function round trip per tick, and up to a second of delay
  // after the teacher had already accepted. The status is pushed to
  // `questions/{qid}` in RTDB the moment it changes, so listen for it instead
  // and let the caller read the answer locally.
  //
  // The LiveKit token deliberately does not travel this way — `questions/$qid`
  // is readable by any signed-in user under the database rules, so the token is
  // still minted by one getQuestionStatus call once acceptance is seen.

#if !os(Android)
  private static var listenerRef: FirebaseDatabase.DatabaseReference?
  private static var listenerHandle: DatabaseHandle?
  private static var listenerQuestionId: String?
  private static var live: LiveQuestionStatus = .pending
#endif

  static func startListening(questionId: String) {
#if os(Android)
    try? jniContext {
      try AndroidQuestionStatusBridge.startListening(questionId: questionId)
    }
#else
    guard listenerQuestionId != questionId || listenerHandle == nil else { return }
    stopListening()

    let ref = FirebaseDatabase.Database.database().reference(withPath: "questions/\(questionId)")
    listenerHandle = ref.observe(.value) { snapshot in
      guard let dict = snapshot.value as? [String: Any],
            let status = dict["status"] as? String,
            !status.isEmpty else {
        live = snapshot.exists() ? .pending : .gone
        return
      }

      live = .ready(
        QuestionStatusResult(
          status: status,
          liveKitRoom: dict["liveKitRoom"] as? String,
          liveKitToken: dict["liveKitToken"] as? String,
          questionId: firstString(in: dict, keys: ["questionId", "questionID", "id"]),
          aiAnswer: dict["aiAnswer"] as? String,
          aiAnswered: dict["aiAnswered"] as? Bool ?? false
        )
      )
    } withCancel: { error in
      logger.error("[QuestionStatus] listener cancelled: \(error)")
      live = .failed
    }
    listenerRef = ref
    listenerQuestionId = questionId
#endif
  }

  static func stopListening() {
#if os(Android)
    try? jniContext {
      try AndroidQuestionStatusBridge.stopListening()
    }
#else
    if let listenerRef, let listenerHandle {
      listenerRef.removeObserver(withHandle: listenerHandle)
    }
    listenerRef = nil
    listenerHandle = nil
    listenerQuestionId = nil
    live = .pending
#endif
  }

  /// Reads what the listener holds. No network on either platform — this is a
  /// memory read (on Android, one JNI hop into the Kotlin listener's cache),
  /// which is what makes it cheap enough to consult several times a second.
  static func latest() -> LiveQuestionStatus {
#if os(Android)
    guard let json = try? jniContext({
      try AndroidQuestionStatusBridge.liveQuestionStatus()
    }) as String? else { return .failed }

    guard let data = json.data(using: .utf8),
          let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let state = envelope["state"] as? String else {
      return .failed
    }

    switch state {
    case "ready":
      guard let row = envelope["question"] as? [String: Any],
            let status = row["status"] as? String,
            !status.isEmpty else { return .pending }
      return .ready(
        QuestionStatusResult(
          status: status,
          liveKitRoom: row["liveKitRoom"] as? String,
          liveKitToken: row["liveKitToken"] as? String,
          questionId: firstString(in: row, keys: ["questionId", "questionID", "id"]),
          aiAnswer: row["aiAnswer"] as? String,
          aiAnswered: row["aiAnswered"] as? Bool ?? false
        )
      )
    case "gone":
      return .gone
    case "pending":
      return .pending
    default:
      return .failed
    }
#else
    return live
#endif
  }

  static func fetch(questionId: String) async throws -> QuestionStatusResult? {
#if os(Android)
    let json = try await Task.detached(priority: .userInitiated) {
      try AndroidQuestionStatusBridge.fetchQuestionStatus(questionId: questionId)
    }.value
    guard let data = json.data(using: .utf8),
          let row = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let status = row["status"] as? String,
          !status.isEmpty else {
      return nil
    }
    return QuestionStatusResult(
      status: status,
      liveKitRoom: row["liveKitRoom"] as? String,
      liveKitToken: row["liveKitToken"] as? String,
      questionId: firstString(in: row, keys: ["questionId", "questionID", "id"]),
      aiAnswer: row["aiAnswer"] as? String,
      aiAnswered: row["aiAnswered"] as? Bool ?? false
    )
#else
    let ref = FirebaseDatabase.Database.database().reference(withPath: "questions/\(questionId)")
    return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<QuestionStatusResult?, Error>) in
      ref.observeSingleEvent(of: .value) { snapshot in
        guard let dict = snapshot.value as? [String: Any],
              let status = dict["status"] as? String,
              !status.isEmpty else {
          cont.resume(returning: nil)
          return
        }

        cont.resume(
          returning: QuestionStatusResult(
            status: status,
            liveKitRoom: dict["liveKitRoom"] as? String,
            liveKitToken: dict["liveKitToken"] as? String,
            questionId: firstString(in: dict, keys: ["questionId", "questionID", "id"]),
            aiAnswer: dict["aiAnswer"] as? String,
            aiAnswered: dict["aiAnswered"] as? Bool ?? false
          )
        )
      } withCancel: { error in
        cont.resume(throwing: error)
      }
    }
#endif
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
}

#if os(Android)
private enum AndroidQuestionStatusBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidChatManager")
  private static let fetchQuestionStatusMethod = managerClass.getStaticMethodID(
    name: "fetchQuestionStatusJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!

  private static let startListenerMethod = managerClass.getStaticMethodID(
    name: "startQuestionStatusListener",
    sig: "(Ljava/lang/String;)V"
  )!
  private static let stopListenerMethod = managerClass.getStaticMethodID(
    name: "stopQuestionStatusListener",
    sig: "()V"
  )!
  private static let liveStatusMethod = managerClass.getStaticMethodID(
    name: "liveQuestionStatusJson",
    sig: "()Ljava/lang/String;"
  )!

  static func fetchQuestionStatus(questionId: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: fetchQuestionStatusMethod,
        options: [.kotlincompat],
        args: [questionId.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }

  static func startListening(questionId: String) throws {
    try managerClass.callStatic(
      method: startListenerMethod,
      options: [.kotlincompat],
      args: [questionId.toJavaParameter(options: [.kotlincompat])]
    ) as Void
  }

  static func stopListening() throws {
    try managerClass.callStatic(
      method: stopListenerMethod,
      options: [.kotlincompat],
      args: []
    ) as Void
  }

  static func liveQuestionStatus() throws -> String {
    try managerClass.callStatic(
      method: liveStatusMethod,
      options: [.kotlincompat],
      args: []
    ) as String
  }
}
#endif
