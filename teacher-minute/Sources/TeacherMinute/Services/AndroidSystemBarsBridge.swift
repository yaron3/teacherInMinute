#if os(Android)
import Foundation
import SkipBridge

/// `AndroidSystemBars.kt`.
enum AndroidSystemBarsBridge {
  private static let barsClass = try! JClass(name: "teacher/minute/AndroidSystemBars")
  private static let setDarkIconsMethod = barsClass.getStaticMethodID(
    name: "setDarkIcons",
    sig: "(Ljava/lang/String;ZZ)V"
  )!
  private static let followThemeMethod = barsClass.getStaticMethodID(
    name: "followTheme",
    sig: "(Ljava/lang/String;)V"
  )!

  static func setDarkIcons(owner: String, statusBar: Bool, navigationBar: Bool) {
    jniContext {
      do {
        try barsClass.callStatic(
          method: setDarkIconsMethod,
          options: [.kotlincompat],
          args: [
            owner.toJavaParameter(options: [.kotlincompat]),
            statusBar.toJavaParameter(options: [.kotlincompat]),
            navigationBar.toJavaParameter(options: [.kotlincompat]),
          ]
        )
      } catch {
        logger.error("[SystemBars][Android] failed to set dark icons status=\(statusBar) navigation=\(navigationBar): \(error)")
      }
    }
  }

  static func followTheme(owner: String) {
    jniContext {
      do {
        try barsClass.callStatic(
          method: followThemeMethod,
          options: [.kotlincompat],
          args: [owner.toJavaParameter(options: [.kotlincompat])]
        )
      } catch {
        logger.error("[SystemBars][Android] failed to hand the bars back to the theme: \(error)")
      }
    }
  }
}
#endif
