#if os(Android)
import Foundation
import SkipBridge

enum AndroidBackNavigationBridge {
    private static let activityClass = try! JClass(name: "teacher/minute/MainActivity")
    private static let setSystemBackBlockedMethod = activityClass.getStaticMethodID(
        name: "setSystemBackBlocked",
        sig: "(Z)V"
    )!
    private static let setSessionBackBlockedMethod = activityClass.getStaticMethodID(
        name: "setSessionBackBlocked",
        sig: "(Z)V"
    )!

    /// Blocks back for the duration of a lesson. Separate from
    /// `setSystemBackBlocked` because that callback is registered before the
    /// navigation stack's own and so cannot outrank it; this one is added when
    /// the lesson starts, and removed when it ends.
    static func setSessionBackBlocked(_ blocked: Bool) {
        jniContext {
            do {
                try activityClass.callStatic(
                    method: setSessionBackBlockedMethod,
                    options: [.kotlincompat],
                    args: [blocked.toJavaParameter(options: [.kotlincompat])]
                )
            } catch {
                logger.error("[BackNav][Android] failed to set sessionBackBlocked=\(blocked): \(error)")
            }
        }
    }

    static func setSystemBackBlocked(_ blocked: Bool) {
        jniContext {
            do {
                try activityClass.callStatic(
                    method: setSystemBackBlockedMethod,
                    options: [.kotlincompat],
                    args: [blocked.toJavaParameter(options: [.kotlincompat])]
                )
            } catch {
                logger.error("[BackNav][Android] failed to set systemBackBlocked=\(blocked): \(error)")
            }
        }
    }
}
#endif
