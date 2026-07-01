#if os(Android)
import Foundation
import SkipBridge

enum AndroidBackNavigationBridge {
    private static let activityClass = try! JClass(name: "teacher/minute/MainActivity")
    private static let setSystemBackBlockedMethod = activityClass.getStaticMethodID(
        name: "setSystemBackBlocked",
        sig: "(Z)V"
    )!

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
