#if os(Android)
import Foundation
import SkipBridge

enum AndroidKeyboardBridge {
    private static let managerClass = try! JClass(name: "teacher/minute/AndroidKeyboardManager")
    private static let hideSoftKeyboardMethod = managerClass.getStaticMethodID(
        name: "hideSoftKeyboard",
        sig: "()V"
    )!

    private static let showSoftKeyboardMethod = managerClass.getStaticMethodID(
        name: "showSoftKeyboard",
        sig: "()V"
    )!
    private static let isSoftKeyboardVisibleMethod = managerClass.getStaticMethodID(
        name: "isSoftKeyboardVisible",
        sig: "()Z"
    )!
    private static let canReportVisibilityMethod = managerClass.getStaticMethodID(
        name: "canReportSoftKeyboardVisibility",
        sig: "()Z"
    )!

    static func hideSoftKeyboard() {
        jniContext {
            do {
                try managerClass.callStatic(
                    method: hideSoftKeyboardMethod,
                    options: [.kotlincompat],
                    args: []
                )
            } catch {
                logger.error("[Keyboard][Android] failed to hide the soft keyboard: \(error)")
            }
        }
    }

    static func showSoftKeyboard() {
        jniContext {
            do {
                try managerClass.callStatic(
                    method: showSoftKeyboardMethod,
                    options: [.kotlincompat],
                    args: []
                )
            } catch {
                logger.error("[Keyboard][Android] failed to show the soft keyboard: \(error)")
            }
        }
    }

    static func canReportSoftKeyboardVisibility() -> Bool {
        let supported: Bool? = try? jniContext {
            let value: Bool = try managerClass.callStatic(
                method: canReportVisibilityMethod,
                options: [.kotlincompat],
                args: []
            )
            return value
        }
        return supported ?? false
    }

    static func isSoftKeyboardVisible() -> Bool {
        let visible: Bool? = try? jniContext {
            let value: Bool = try managerClass.callStatic(
                method: isSoftKeyboardVisibleMethod,
                options: [.kotlincompat],
                args: []
            )
            return value
        }
        return visible ?? false
    }
}
#endif
