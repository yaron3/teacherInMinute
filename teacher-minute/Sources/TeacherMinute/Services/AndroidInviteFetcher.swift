#if os(Android)
import Foundation
import SkipBridge

enum AndroidInviteFetcher {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidInviteManager")
  private static let fetchInvitesJsonMethod = managerClass.getStaticMethodID(
    name: "fetchInvitesJson",
    sig: "(Ljava/lang/String;)Ljava/lang/String;"
  )!

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
