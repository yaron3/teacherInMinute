import Foundation

#if os(Android)
import SkipBridge
#else
import FirebaseDatabase
#endif

/// Is anyone available to take a question right now?
///
/// Reads the public `onlineTeachers` projection, not `teachers`. `teachers` is
/// owner-only under the database rules, so a student asking that node was
/// always denied — the read failed, the catch assumed availability, and the
/// check cost a round trip on the ask path without ever answering anything.
/// The projection holds only teachers who are online, so its emptiness *is*
/// the answer, and it is a fraction of the size.
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
    let ref = FirebaseDatabase.Database.database().reference(withPath: "onlineTeachers")
    return await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
      ref.observeSingleEvent(of: .value) { snapshot in
        cont.resume(returning: snapshot.hasChildren())
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
