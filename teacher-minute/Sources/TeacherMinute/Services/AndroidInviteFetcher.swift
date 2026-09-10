#if os(Android)
import Foundation
import SkipBridge

enum AndroidInviteFetcher {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidInviteManager")
  private static let fetchInvitesJsonMethod = managerClass.getStaticMethodID(
    name: "fetchInvitesJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!

  private static let startListeningMethod = managerClass.getStaticMethodID(
    name: "startListening",
    sig: "(Ljava/lang/String;)V"
  )!
  private static let stopListeningMethod = managerClass.getStaticMethodID(
    name: "stopListening",
    sig: "()V"
  )!
  private static let liveInvitesJsonMethod = managerClass.getStaticMethodID(
    name: "liveInvitesJson",
    sig: "()Ljava/lang/String;"
  )!

  /// What the Kotlin listener currently holds.
  enum LiveInvites {
    /// A snapshot has arrived — these are the invites, empty list included.
    case ready([[String: Any]])
    /// The listener is attached but has not delivered yet.
    case pending
    /// The listener was cancelled; the caller should fall back to a fetch.
    case failed
  }

  /// Attaches the Kotlin-side RTDB listener. Idempotent per teacher.
  static func startListening(teacherId: String) {
    try? jniContext {
      try managerClass.callStatic(
        method: startListeningMethod,
        options: [.kotlincompat],
        args: [teacherId.toJavaParameter(options: [.kotlincompat])]
      ) as Void
    }
  }

  static func stopListening() {
    try? jniContext {
      try managerClass.callStatic(
        method: stopListeningMethod,
        options: [.kotlincompat],
        args: []
      ) as Void
    }
  }

  /// Reads the listener's cache. No network — this is a JNI call into memory,
  /// which is what makes it cheap enough to run several times a second.
  static func liveInvites() -> LiveInvites {
    guard let json = try? jniContext({
      try managerClass.callStatic(
        method: liveInvitesJsonMethod,
        options: [.kotlincompat],
        args: []
      )
    }) as String? else { return .failed }

    guard let data = json.data(using: .utf8),
          let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let state = envelope["state"] as? String else {
      return .failed
    }

    switch state {
    case "ready":
      return .ready(envelope["invites"] as? [[String: Any]] ?? [])
    case "pending":
      return .pending
    default:
      return .failed
    }
  }

  static func fetchInvites(teacherId: String) async throws -> [[String: Any]] {
    let json = try await Task.detached(priority: .userInitiated) {
      try jniContext {
        try managerClass.callStatic(
          method: fetchInvitesJsonMethod,
          options: [.kotlincompat],
          args: [teacherId.toJavaParameter(options: [.kotlincompat])]
        )
      } as String
    }.value

    guard let data = json.data(using: .utf8),
          let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      return []
    }

    return rows
  }
}
#endif
