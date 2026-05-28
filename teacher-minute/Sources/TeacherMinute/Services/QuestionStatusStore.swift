import Foundation

#if os(Android)
import SkipBridge
#else
import FirebaseDatabase
#endif

@MainActor
enum QuestionStatusStore {
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

  static func fetchQuestionStatus(questionId: String) throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: fetchQuestionStatusMethod,
        options: [.kotlincompat],
        args: [questionId.toJavaParameter(options: [.kotlincompat])]
      )
    } as String
  }
}
#endif
