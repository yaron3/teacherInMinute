#if os(Android)
import Foundation
import SkipBridge

/// The launch splash's art as a native Android drawable
/// (`AndroidSplashArtView.kt`), for `LaunchSplashView` to embed.
enum AndroidSplashArtBridge {
    private static let viewClass = try! JClass(name: "teacher/minute/AndroidSplashArtView")
    private static let createMethod = viewClass.getStaticMethodID(
        name: "create",
        sig: "()Lskip/ui/ComposeView;"
    )!

    /// One composer serves every render of the splash.
    static let composer: AndroidJavaObject? = jniContext {
        do {
            return try viewClass.callStatic(method: createMethod, options: [.kotlincompat], args: [])
        } catch {
            logger.error("[Splash][Android] failed to create the splash art view: \(error)")
            return nil
        }
    }
}
#endif
