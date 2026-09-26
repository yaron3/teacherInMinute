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
    private static let sendKeepAliveMethod = managerClass.getStaticMethodID(
        name: "sendKeepAlive",
        sig: "(Ljava/lang/String;)V"
    )!

    /// One keep-alive for `uid` — see `TeacherKeepAlive`. Named rather than
    /// taken from the signed-in user, so it can never land on another account.
    static func sendKeepAlive(uid: String) {
        jniContext {
            do {
                try managerClass.callStatic(
                    method: sendKeepAliveMethod,
                    options: [.kotlincompat],
                    args: [uid.toJavaParameter(options: [.kotlincompat])]
                )
            } catch {
                logger.error("[Presence] Android keep-alive call failed: \(error)")
            }
        }
    }

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
