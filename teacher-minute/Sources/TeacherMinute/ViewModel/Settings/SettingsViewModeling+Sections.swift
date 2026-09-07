//
//  SettingsViewModeling+Sections.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

extension SettingsViewModeling {

    var appVersion: String {
        let appName = LocalizationSupport.localized("Teacher in a Minute App")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String

        switch (version?.isEmpty == false ? version : nil, build?.isEmpty == false ? build : nil) {
        case let (.some(version), .some(build)):
            return "\(appName) - \(version) (\(build))"
        case let (.some(version), .none):
            return "\(appName) - \(version)"
        case let (.none, .some(build)):
            return "\(appName) - \(build)"
        case (.none, .none):
            return appName
        }
    }

    var preferenceRows: [SettingsRow] {
        var rows = [
            SettingsRow(
                title: LocalizationSupport.localized("Preferences"),
                subtitle: role == .teacher
                    ? LocalizationSupport.localized("Currency")
                    : LocalizationSupport.localized("Default session type and currency"),
                systemImage: "slider.horizontal.3",
                iconColor: .primary,
                isDestructive: false,
                action: .appPreferences
            ),
            SettingsRow(
                title: LocalizationSupport.localized("Language"),
                subtitle: selectedLanguage.title,
                systemImage: "globe",
                iconColor: .primary,
                isDestructive: false,
                action: .language
            ),
            SettingsRow(
                title: LocalizationSupport.localized("Notification Preferences"),
                subtitle: nil,
                systemImage: "bell.fill",
                iconColor: .primary,
                isDestructive: false,
                action: .notifications
            ),
            SettingsRow(
                title: LocalizationSupport.localized("Privacy Controls"),
                subtitle: nil,
                systemImage: "shield.lefthalf.filled",
                iconColor: .primary,
                isDestructive: false,
                action: .privacyControls
            )
        ]

        #if DEBUG
        rows.append(
            SettingsRow(
                title: LocalizationSupport.localized("Force Reload Remote Config"),
                subtitle: LocalizationSupport.localized("Debug builds only"),
                systemImage: "arrow.clockwise",
                iconColor: .primary,
                isDestructive: false,
                action: .forceReloadRemoteConfig
            )
        )
        rows.append(
            SettingsRow(
                title: LocalizationSupport.localized("Test Crashlytics Crash"),
                subtitle: LocalizationSupport.localized("Debug builds only"),
                systemImage: "exclamationmark.triangle.fill",
                iconColor: .red,
                isDestructive: true,
                action: .testCrashlyticsCrash
            )
        )
        #endif

        return rows
    }

    var sections: [SettingsSection] {
        [
            role == .teacher ? SettingsSection(
                title: LocalizationSupport.localized("PAYOUTS"),
                rows: [
                    SettingsRow(
                        title: LocalizationSupport.localized("Teacher Payout Settings"),
                        subtitle: LocalizationSupport.localized("Update PayPal payout email"),
                        systemImage: "banknote.fill",
                        iconColor: .purple,
                        isDestructive: false,
                        action: .teacherPayouts
                    )
                ]
            ): SettingsSection(
                title: LocalizationSupport.localized("PAYMENTS"),
                rows: [
                    SettingsRow(
                        title: LocalizationSupport.localized("Payment History"),
                        subtitle: LocalizationSupport.localized("View your lesson payment history"),
                        systemImage: "creditcard.fill",
                        iconColor: .pink,
                        isDestructive: false,
                        action: .studentPayments
                    )
                ]
            ),
            SettingsSection(
                title: LocalizationSupport.localized("PREFERENCES"),
                rows: preferenceRows
            ),
            SettingsSection(
                title: LocalizationSupport.localized("ABOUT"),
                rows: [
                    SettingsRow(
                        title: LocalizationSupport.localized("About"),
                        subtitle: nil,
                        systemImage: "doc.text.fill",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .about
                    )
                ]
            ),
            SettingsSection(
                title: LocalizationSupport.localized("ACCOUNT"),
                rows: [
                    SettingsRow(
                        title: LocalizationSupport.localized("Account & Security"),
                        subtitle: LocalizationSupport.localized("Password, logout and account removal"),
                        systemImage: "lock.fill",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .accountSecurity
                    )
                ]
            )
        ]
    }

    var accountSecuritySection: SettingsSection {
        SettingsSection(
            title: LocalizationSupport.localized("ACCOUNT & SECURITY"),
            rows: [
                SettingsRow(
                    title: LocalizationSupport.localized("Change Password"),
                    subtitle: nil,
                    systemImage: "lock.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .changePassword
                ),
                SettingsRow(
                    title: LocalizationSupport.localized("Log Out"),
                    subtitle: nil,
                    systemImage: "rectangle.portrait.and.arrow.right",
                    iconColor: .red,
                    isDestructive: true,
                    action: .logOut
                ),
                SettingsRow(
                    title: LocalizationSupport.localized("Delete Account"),
                    subtitle: LocalizationSupport.localized("Permanently remove your account"),
                    systemImage: "trash.fill",
                    iconColor: .red,
                    isDestructive: true,
                    action: .deleteAccount
                )
            ]
        )
    }

    var aboutSection: SettingsSection {
        SettingsSection(
            title: LocalizationSupport.localized("ABOUT"),
            rows: [
                SettingsRow(
                    title: LocalizationSupport.localized("Contact Us"),
                    subtitle: nil,
                    systemImage: "envelope.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .contactUs
                ),
                SettingsRow(
                    title: LocalizationSupport.localized("EULA"),
                    subtitle: nil,
                    systemImage: "doc.plaintext.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .eula
                ),
                SettingsRow(
                    title: LocalizationSupport.localized("Privacy Policy"),
                    subtitle: nil,
                    systemImage: "hand.raised.fill",
                    iconColor: .primary,
                    isDestructive: false,
                    action: .privacyPolicy
                )
            ]
        )
    }

    /// Row routing is identical for the live and mock view models — only the
    /// handlers they land on differ — so it lives here and both inherit it.
    func select(_ row: SettingsRow) {
        switch row.action {
        case .accountSecurity:
            navigationPath.append(.accountSecurity)
        case .appPreferences:
            navigationPath.append(.appPreferences)
        case .changePassword:
            sendPasswordReset()
        case .teacherPayouts:
            navigationPath.append(.teacherPayouts)
        case .studentPayments:
            navigationPath.append(.studentPayments)
        case .notifications:
            navigationPath.append(.notifications)
        case .privacyControls:
            navigationPath.append(.privacyControls)
        case .language:
            navigationPath.append(.language)
        case .about:
            navigationPath.append(.about)
        case .contactUs:
            navigationPath.append(.contactUs)
        case .eula:
            Task { await openEULA() }
        case .privacyPolicy:
            Task { await openPrivacyPolicy() }
        #if DEBUG
        case .forceReloadRemoteConfig:
            Task { await forceReloadRemoteConfig() }
        case .testCrashlyticsCrash:
            AnalyticsService.shared.triggerCrashlyticsTestCrash()
        #endif
        case .logOut:
            activeConfirmation = .logOut
        case .deleteAccount:
            activeConfirmation = .deleteAccount
        }
    }

    func confirm(_ confirmation: SettingsConfirmation) async -> Bool {
        switch confirmation {
        case .logOut:
            return logOut()
        case .deleteAccount:
            return await deleteAccount()
        }
    }

    func present(message: String) {
        present(title: settingsTitle, message: message)
    }
}
