#if os(Android)
import Foundation
import SkipBridge

enum AndroidLocaleBridge {
    private static let managerClass = try! JClass(name: "teacher/minute/AndroidLocaleManager")
    private static let applyLanguageCodeMethod = managerClass.getStaticMethodID(
        name: "applyLanguageCode",
        sig: "(Ljava/lang/String;)Ljava/lang/String;"
    )!

    static func applyLanguageCode(_ languageCode: String) {
        jniContext {
            do {
                let appliedTag = try managerClass.callStatic(
                    method: applyLanguageCodeMethod,
                    options: [.kotlincompat],
                    args: [languageCode.toJavaParameter(options: [.kotlincompat])]
                ) as String
                logger.info("[Localization][Android] applied JVM locale languageCode=\(languageCode) appliedTag=\(appliedTag)")
            } catch {
                logger.error("[Localization][Android] failed to apply JVM locale languageCode=\(languageCode): \(error)")
            }
        }
    }
}
#endif
