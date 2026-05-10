//
//  AndroidTeacherPresenceWriter.swift
//  teacher-minute
//

#if os(Android)
import Foundation
import SkipBridge

enum AndroidTeacherPresenceWriter {
    private static let managerClass = try! JClass(name: "teacher/minute/AndroidTeacherPresenceManager")
    private static let setCurrentTeacherStatusMethod = managerClass.getStaticMethodID(
        name: "setCurrentTeacherStatus",
        sig: "(Ljava/lang/String;)V"
    )!

    static func setCurrentTeacherStatus(_ status: String) {
        jniContext {
            do {
                try managerClass.callStatic(
                    method: setCurrentTeacherStatusMethod,
                    options: [.kotlincompat],
                    args: [status.toJavaParameter(options: [.kotlincompat])]
                )
                logger.info("[Presence] requested Android Firebase SDK status write status=\(status)")
            } catch {
                logger.error("[Presence] Android Firebase SDK status write call failed: \(error)")
            }
        }
    }
}
#endif
