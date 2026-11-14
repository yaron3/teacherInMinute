//
//  AndroidPushTokenWriter.swift
//  teacher-minute
//

#if os(Android)
import Foundation
import SkipBridge

enum AndroidPushTokenWriter {
    private static let managerClass = try! JClass(name: "teacher/minute/AndroidPushTokenManager")
    private static let writeTokenMethod = managerClass.getStaticMethodID(
        name: "writeToken",
        sig: "(Ljava/lang/String;Ljava/lang/String;Z)V"
    )!

    private static let writePreferencesMethod = managerClass.getStaticMethodID(
        name: "writeNotificationPreferences",
        sig: "(Ljava/lang/String;ZZZ)V"
    )!

    /// The user's notification choices, next to the push token (IT-28).
    static func writeNotificationPreferences(_ preferences: NotificationPreferences, uid: String, isTeacher: Bool) {
        jniContext {
            do {
                try managerClass.callStatic(
                    method: writePreferencesMethod,
                    options: [.kotlincompat],
                    args: [
                        uid.toJavaParameter(options: [.kotlincompat]),
                        isTeacher.toJavaParameter(options: [.kotlincompat]),
                        preferences.incomingMessages.toJavaParameter(options: [.kotlincompat]),
                        preferences.announcements.toJavaParameter(options: [.kotlincompat])
                    ]
                )
                logger.info("[Push] requested Android notification preferences write uid=\(uid) incoming=\(preferences.incomingMessages) announcements=\(preferences.announcements)")
            } catch {
                logger.error("[Push] Android notification preferences write call failed: \(error)")
            }
        }
    }

    static func writeToken(_ token: String, uid: String, isTeacher: Bool) {
        jniContext {
            do {
                try managerClass.callStatic(
                    method: writeTokenMethod,
                    options: [.kotlincompat],
                    args: [
                        token.toJavaParameter(options: [.kotlincompat]),
                        uid.toJavaParameter(options: [.kotlincompat]),
                        isTeacher.toJavaParameter(options: [.kotlincompat])
                    ]
                )
                logger.info("[Push] requested Android FCM token write uid=\(uid) isTeacher=\(isTeacher)")
            } catch {
                logger.error("[Push] Android FCM token write call failed: \(error)")
            }
        }
    }
}
#endif
