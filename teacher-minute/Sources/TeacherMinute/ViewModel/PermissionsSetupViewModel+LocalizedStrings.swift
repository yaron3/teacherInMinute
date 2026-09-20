//
//  PermissionsSetupViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the permissions onboarding step.
//

import Foundation

extension PermissionsSetupViewModel {
    var screenTitle: String { LocalizationSupport.localized("Connect & Learn") }
    var introText: String {
        LocalizationSupport.localized("To give you the best math tutoring\nexperience, we need a couple of\npermissions to connect you instantly.")
    }

    var microphoneCardTitle: String { LocalizationSupport.localized("Microphone") }
    var microphoneCardSubtitle: String {
        LocalizationSupport.localized("Talk live with\nteachers to solve\nmath problems\ntogether in real-\ntime.")
    }
    var cameraCardTitle: String { LocalizationSupport.localized("Camera") }
    var cameraCardSubtitle: String {
        LocalizationSupport.localized("Use video in live\nlessons and update\nyour profile photo\nwhen needed.")
    }

    var continueSetupLabel: String { LocalizationSupport.localized("Continue Setup") }
    var skipLabel: String { LocalizationSupport.localized("Not now, use limited mode") }
}
