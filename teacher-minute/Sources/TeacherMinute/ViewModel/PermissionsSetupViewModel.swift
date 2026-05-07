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
    var notificationsEnabled = true

    var onContinue: (() -> Void)?

    func continueSetup() {
        // TODO: request actual system permissions
        onContinue?()
    }

    func limitedMode() {
        onContinue?()
    }
}
