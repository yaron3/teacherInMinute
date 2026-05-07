//
//  SettingsSection.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import Observation
import Foundation
import SwiftUI

struct SettingsSection: Identifiable {
    let id = UUID()
    let title: String
    let rows: [SettingsRow]
}

struct SettingsRow: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String?
    let systemImage: String
    let iconColor: SettingsIconColor
    let isDestructive: Bool
}

enum SettingsIconColor {
    case primary
    case pink
    case purple
    case red

    var foregroundColor: Color {
        switch self {
        case .primary: .appPrimaryText
        case .pink: .appPink
        case .purple: .appPurple
        case .red: .red
        }
    }

    var backgroundColor: Color {
        switch self {
        case .primary: .appGrayBackground
        case .pink: .appPinkSoft
        case .purple: .appPurpleSoft
        case .red: Color.red.opacity(0.08)
        }
    }
}

@Observable
final class SettingsViewModel {
    let appVersion = "Math Connect App v2.4.1"

    var sections: [SettingsSection] {
        [
            SettingsSection(
                title: "ACCOUNT & SECURITY",
                rows: [
                    SettingsRow(
                        title: "Change Password",
                        subtitle: nil,
                        systemImage: "lock.fill",
                        iconColor: .primary,
                        isDestructive: false
                    ),
                    SettingsRow(
                        title: "Log Out",
                        subtitle: nil,
                        systemImage: "rectangle.portrait.and.arrow.right",
                        iconColor: .red,
                        isDestructive: true
                    )
                ]
            ),
            SettingsSection(
                title: "PAYMENTS & PAYOUTS",
                rows: [
                    SettingsRow(
                        title: "Teacher Payout Settings",
                        subtitle: "Manage bank details & history",
                        systemImage: "banknote.fill",
                        iconColor: .purple,
                        isDestructive: false
                    ),
                    SettingsRow(
                        title: "Student Payment Methods",
                        subtitle: "Cards & billing history",
                        systemImage: "creditcard.fill",
                        iconColor: .pink,
                        isDestructive: false
                    )
                ]
            ),
            SettingsSection(
                title: "PREFERENCES",
                rows: [
                    SettingsRow(
                        title: "Notification Preferences",
                        subtitle: nil,
                        systemImage: "bell.fill",
                        iconColor: .primary,
                        isDestructive: false
                    ),
                    SettingsRow(
                        title: "Privacy Controls",
                        subtitle: nil,
                        systemImage: "shield.lefthalf.filled",
                        iconColor: .primary,
                        isDestructive: false
                    )
                ]
            ),
            SettingsSection(
                title: "ABOUT",
                rows: [
                    SettingsRow(
                        title: "Help & Support",
                        subtitle: nil,
                        systemImage: "questionmark.circle.fill",
                        iconColor: .primary,
                        isDestructive: false
                    ),
                    SettingsRow(
                        title: "Legal & Terms",
                        subtitle: nil,
                        systemImage: "doc.text.fill",
                        iconColor: .primary,
                        isDestructive: false
                    )
                ]
            )
        ]
    }

    func select(_ row: SettingsRow) {
        // TODO: route based on row.title or use an enum-backed row model
    }
}
