#if os(Android)
import Foundation
import SkipBridge

enum AndroidCrashlyticsBridge {
    private static let managerClass = try! JClass(name: "teacher/minute/AndroidCrashlyticsManager")
    private static let triggerTestCrashMethod = managerClass.getStaticMethodID(
        name: "triggerTestCrash",
        sig: "()V"
    )!

    static func triggerTestCrash() {
        jniContext {
            do {
                try managerClass.callStatic(
                    method: triggerTestCrashMethod,
                    options: [.kotlincompat],
                    args: []
                )
            } catch {
                logger.error("[Crashlytics][Android] failed to trigger test crash: \(error)")
            }
        }
    }
}
#endif
