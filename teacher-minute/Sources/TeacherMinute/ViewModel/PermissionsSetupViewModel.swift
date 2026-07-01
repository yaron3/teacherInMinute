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

    var onContinue: (() -> Void)?

    func continueSetup() {
        Task {
            if microphoneEnabled {
                microphoneEnabled = await PermissionService.shared.requestCapturePermission(for: .microphone) == .granted
            }
            if cameraEnabled {
                cameraEnabled = await PermissionService.shared.requestCapturePermission(for: .camera) == .granted
            }
            // Notification permission is intentionally NOT requested here. It is
            // requested only after the student's first lesson, behind a custom
            // explanatory prompt. See NotificationPromptStore.
            onContinue?()
        }
    }

    func limitedMode() {
        onContinue?()
    }
}
