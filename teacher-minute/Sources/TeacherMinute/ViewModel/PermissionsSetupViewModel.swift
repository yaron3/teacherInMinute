//
//  PermissionsSetupViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class PermissionsSetupViewModel {
    var microphoneEnabled = true
    var cameraEnabled = true
    var notificationsEnabled = true

    var onContinue: (() -> Void)?

    func continueSetup() {
        Task {
            if microphoneEnabled {
                microphoneEnabled = await PermissionService.shared.requestCapturePermission(for: .microphone) == .granted
            }
            if cameraEnabled {
                cameraEnabled = await PermissionService.shared.requestCapturePermission(for: .camera) == .granted
            }
            if notificationsEnabled {
                notificationsEnabled = await PermissionService.shared.requestNotifications() == .granted
            }
            onContinue?()
        }
    }

    func limitedMode() {
        onContinue?()
    }
}
