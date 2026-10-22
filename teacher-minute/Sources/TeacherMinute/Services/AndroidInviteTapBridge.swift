#if os(Android)
import Foundation
import SkipBridge

/// Collects the invite notification tap MainActivity holds; see
/// `MainActivity.takeTappedInviteQuestionId`.
enum AndroidInviteTapBridge {
  private static let activityClass = try! JClass(name: "teacher/minute/MainActivity")
  private static let takeTappedInviteQuestionIdMethod = activityClass.getStaticMethodID(
    name: "takeTappedInviteQuestionId",
    sig: "()Ljava/lang/String;"
  )!

  /// The question whose notification was tapped since the last call, if any.
  static func takeTappedQuestionId() -> String? {
    guard let questionId = try? jniContext({
      try activityClass.callStatic(
        method: takeTappedInviteQuestionIdMethod,
        options: [.kotlincompat],
        args: []
      )
    }) as String?, !questionId.isEmpty else { return nil }
    return questionId
  }
}
#endif
