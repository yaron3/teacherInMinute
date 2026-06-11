#if os(Android)
import Foundation
import SkipBridge

enum AndroidLocaleBridge {
    private static let managerClass = try! JClass(name: "teacher/minute/AndroidLocaleManager")
    private static let applyLanguageCodeMethod = managerClass.getStaticMethodID(
        name: "applyLanguageCode",
        sig: "(Ljava/lang/String;)Ljava/lang/String;"
    )!
    private static let applyRemoteConfigLanguageSignalMethod = managerClass.getStaticMethodID(
        name: "applyRemoteConfigLanguageSignal",
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

    static func applyRemoteConfigLanguageSignal(_ languageCode: String) {
        jniContext {
            do {
                let appliedCode = try managerClass.callStatic(
                    method: applyRemoteConfigLanguageSignalMethod,
                    options: [.kotlincompat],
                    args: [languageCode.toJavaParameter(options: [.kotlincompat])]
                ) as String
                logger.info("[Localization][Android] applied Remote Config custom signal languageCode=\(languageCode) appliedCode=\(appliedCode)")
            } catch {
                logger.error("[Localization][Android] failed to apply Remote Config custom signal languageCode=\(languageCode): \(error)")
            }
        }
    }
}
#endif
