//
//  SettingsRow.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct SettingsRow: Identifiable {
    let title: String
    let subtitle: String?
    let systemImage: String
    let iconColor: Color
    let isDestructive: Bool
    let action: SettingsAction
    let destination: SettingsDestination?

    var id: String { "\(title)-\(action.id)" }

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        iconColor: Color,
        isDestructive: Bool = false,
        action: SettingsAction
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.isDestructive = isDestructive
        self.action = action
        // Map actions that have in-stack destinations to SettingsDestination
        switch action {
        case .accountSecurity:
		self.destination = .accountSecurity
        case .appPreferences:  self.destination = .appPreferences
        case .changePassword:  self.destination = .changePassword
        case .teacherPayouts:  self.destination = .teacherPayouts
        case .studentPayments: self.destination = .studentPayments
        case .notifications:   self.destination = .notifications
        case .privacyControls: self.destination = .privacyControls
        case .language:        self.destination = .language
        case .about:           self.destination = .about
        case .eula:
            // EULA/PrivacyPolicy are opened via remote URL; keep destination nil so viewModel handles it
            self.destination = nil
        case .privacyPolicy:
            self.destination = nil
        case .contactUs:
            self.destination = .contactUs
        #if DEBUG
        case .forceReloadRemoteConfig:
            self.destination = nil
        case .testCrashlyticsCrash:
            self.destination = nil
        #endif
        case .logOut, .deleteAccount:
            // Destructive actions handled via confirmation; no navigation
            self.destination = nil
        }
    }
}

//enum SettingsIconColor {
//    case primary
//    case pink
//    case purple
//    case red
//
//    var foregroundColor: Color {
//        switch self {
//        case .primary: .appPrimaryText
//        case .pink: .appPink
//        case .purple: .appPurple
//        case .red: .red
//        }
//    }
//
//    var backgroundColor: Color {
//        switch self {
//        case .primary: .appGrayBackground
//        case .pink: .appPinkSoft
//        case .purple: .appPurpleSoft
//        case .red: .red.opacity(0.08)
//        }
//    }
//}
