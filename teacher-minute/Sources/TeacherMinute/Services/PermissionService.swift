//
//  PermissionService.swift
//  teacher-minute
//
//  Created by Codex on 16/05/2026.
//

import Foundation

#if !os(Android)
import AVFoundation
import UserNotifications
#if os(iOS)
import UIKit
#endif
#else
import SkipBridge
#endif

@MainActor
final class PermissionService {
    static let shared = PermissionService()

    private init() {}

    func captureStatus(for kind: CapturePermissionKind) -> PermissionState {
#if !os(Android)
        switch AVCaptureDevice.authorizationStatus(for: kind.mediaType) {
        case .authorized:
            return .granted
        case .denied, .restricted:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
#else
        return .notDetermined
#endif
    }

    func requestCapturePermission(for kind: CapturePermissionKind) async -> PermissionState {
#if !os(Android)
        let status = AVCaptureDevice.authorizationStatus(for: kind.mediaType)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: kind.mediaType)
            return granted ? .granted : .denied
        }
        return captureStatus(for: kind)
#else
        do {
            let granted = try await Task.detached(priority: .userInitiated) {
                try AndroidPermissionBridge.requestPermission(kind.androidPermission)
            }.value
            return granted ? .granted : .denied
        } catch {
            logger.error("[Permissions] Android capture request failed: \(error.localizedDescription)")
            return captureStatus(for: kind)
        }
#endif
    }

    func notificationStatus() async -> PermissionState {
#if !os(Android)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
#else
        // POST_NOTIFICATIONS reports granted or not: `checkSelfPermission`
        // answers false both for "denied" and for "never asked", so the two
        // cannot be told apart here and an ungranted permission reads as
        // .denied. `hasPermission` already returns true below API 33, where the
        // runtime permission does not exist. This previously returned
        // .notDetermined unconditionally, so the profile's notification row —
        // and the teacher availability rule that now depends on it — read as
        // unknown on every Android device.
        return AndroidPermissionBridge.hasPermission(AndroidPermissionBridge.postNotifications)
            ? .granted
            : .denied
#endif
    }

    func requestNotifications() async -> PermissionState {
#if !os(Android)
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            logger.error("[Permissions] notification request failed: \(error.localizedDescription)")
        }
        return await notificationStatus()
#else
        do {
            let granted = try await Task.detached(priority: .userInitiated) {
                try AndroidPermissionBridge.requestPermission(AndroidPermissionBridge.postNotifications)
            }.value
            return granted ? .granted : .denied
        } catch {
            logger.error("[Permissions] Android notification request failed: \(error.localizedDescription)")
            return await notificationStatus()
        }
#endif
    }

    func openAppSettings() {
#if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
#elseif os(Android)
        do {
            try AndroidPermissionBridge.openAppSettings()
        } catch {
            logger.error("[Permissions] Android openAppSettings failed: \(error.localizedDescription)")
        }
#endif
    }
}

enum CapturePermissionKind {
    case microphone
    case camera

#if !os(Android)
    var mediaType: AVMediaType {
        switch self {
        case .microphone: return .audio
        case .camera: return .video
        }
    }
#else
    var androidPermission: String {
        switch self {
        case .microphone: return "android.permission.RECORD_AUDIO"
        case .camera: return "android.permission.CAMERA"
        }
    }
#endif
}

enum PermissionState: String {
    case notDetermined
    case granted
    case denied

    var isGranted: Bool { self == .granted }

    var subtitle: String {
        switch self {
        case .notDetermined: return LocalizationSupport.localized("Not requested")
        case .granted: return LocalizationSupport.localized("Enabled")
        case .denied: return LocalizationSupport.localized("Disabled")
        }
    }

    var actionTitle: String {
        switch self {
        case .notDetermined: return LocalizationSupport.localized("Enable")
        case .granted: return LocalizationSupport.localized("Manage")
        case .denied: return LocalizationSupport.localized("Settings")
        }
    }
}

#if os(Android)
private enum AndroidPermissionBridge {
    static let postNotifications = "android.permission.POST_NOTIFICATIONS"

    private static let managerClass = try! JClass(name: "teacher/minute/AndroidPermissionManager")
    private static let hasPermissionMethod = managerClass.getStaticMethodID(
        name: "hasPermission",
        sig: "(Ljava/lang/String;)Z"
    )!
    private static let requestPermissionMethod = managerClass.getStaticMethodID(
        name: "requestPermission",
        sig: "(Ljava/lang/String;)Z"
    )!
    private static let openAppSettingsMethod = managerClass.getStaticMethodID(
        name: "openAppSettings",
        sig: "()V"
    )!

    static func openAppSettings() throws {
        try jniContext {
            try managerClass.callStatic(
                method: openAppSettingsMethod,
                options: [.kotlincompat],
                args: []
            )
        }
    }

    static func hasPermission(_ permission: String) -> Bool {
        // `callStatic` picks its JNI call from the return type it is asked for,
        // and that has to be spelled out here. Wrapping it in `try? ... ?? false`
        // breaks the inference chain that `requestPermission` gets for free from
        // its declared `-> Bool`, and it resolved to CallStaticObjectMethodA
        // against a method returning `boolean` — which aborts the process with
        // "JNI DETECTED ERROR IN APPLICATION" rather than failing gracefully.
        // Nothing called this until notificationStatus() did, so the mismatch
        // sat here unexercised.
        let granted: Bool? = try? jniContext {
            let value: Bool = try managerClass.callStatic(
                method: hasPermissionMethod,
                options: [.kotlincompat],
                args: [permission.toJavaParameter(options: [.kotlincompat])]
            )
            return value
        }
        return granted ?? false
    }

    static func requestPermission(_ permission: String) throws -> Bool {
        try jniContext {
            try managerClass.callStatic(
                method: requestPermissionMethod,
                options: [.kotlincompat],
                args: [permission.toJavaParameter(options: [.kotlincompat])]
            )
        }
    }
}
#endif
