import Foundation

#if os(Android)
import SkipBridge
#else
import FirebaseDatabase
#endif

@MainActor
enum TeacherAvailabilityStore {
  static func hasOnlineTeacher() async -> Bool {
#if os(Android)
    do {
      return try await Task.detached(priority: .userInitiated) {
        try AndroidTeacherAvailabilityBridge.hasOnlineTeacher()
      }.value
    } catch {
      logger.error("[TeacherAvailability] Android check failed: \(error); assuming available")
      return true
    }
#else
    let ref = FirebaseDatabase.Database.database().reference(withPath: "teachers")
    return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
      ref.observeSingleEvent(of: .value) { snapshot in
        for case let child as DataSnapshot in snapshot.children {
          if let dict = child.value as? [String: Any],
             let status = dict["status"] as? String,
             status == "online" {
            cont.resume(returning: true)
            return
          }
        }
        cont.resume(returning: false)
      } withCancel: { error in
        logger.error("[TeacherAvailability] iOS check failed: \(error); assuming available")
        cont.resume(returning: true)
      }
    }
#endif
  }
}

#if os(Android)
private enum AndroidTeacherAvailabilityBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidTeacherPresenceManager")
  private static let hasOnlineTeacherMethod = managerClass.getStaticMethodID(
    name: "hasOnlineTeacher",
    sig: "()Z"
  )!

  static func hasOnlineTeacher() throws -> Bool {
    try jniContext {
      try managerClass.callStatic(
        method: hasOnlineTeacherMethod,
        options: [.kotlincompat],
        args: []
      )
    } as Bool
  }
}
#endif
