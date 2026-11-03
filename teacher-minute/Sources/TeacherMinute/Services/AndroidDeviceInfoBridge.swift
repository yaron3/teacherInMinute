//
//  AndroidDeviceInfoBridge.swift
//  teacher-minute
//

#if os(Android)
import Foundation
import SkipBridge

enum AndroidDeviceInfoBridge {
    private static let managerClass = try! JClass(name: "teacher/minute/AndroidDeviceInfoManager")
    private static let osVersionMethod = managerClass.getStaticMethodID(
        name: "osVersion",
        sig: "()Ljava/lang/String;"
    )!
    private static let deviceModelMethod = managerClass.getStaticMethodID(
        name: "deviceModel",
        sig: "()Ljava/lang/String;"
    )!

    /// Manufacturer and model, e.g. "Google Pixel 3", or `nil` when it cannot
    /// be read. See `AndroidDeviceInfoManager.deviceModel`.
    static func deviceModel() -> String? {
        jniContext {
            do {
                let model = try managerClass.callStatic(
                    method: deviceModelMethod,
                    options: [.kotlincompat],
                    args: []
                ) as String
                return model.isEmpty ? nil : model
            } catch {
                logger.error("[DeviceInfo][Android] failed to read device model: \(error)")
                return nil
            }
        }
    }

    /// The Android release, e.g. "14", or `nil` when it cannot be read. See
    /// `AndroidDeviceInfoManager.osVersion`.
    static func osVersion() -> String? {
        jniContext {
            do {
                let version = try managerClass.callStatic(
                    method: osVersionMethod,
                    options: [.kotlincompat],
                    args: []
                ) as String
                return version.isEmpty ? nil : version
            } catch {
                logger.error("[DeviceInfo][Android] failed to read OS version: \(error)")
                return nil
            }
        }
    }
}
#endif
