//
//  SettingsViewModeling+Sections.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

extension SettingsViewModeling {

    var appVersion: String {
        let appName = AuthRole.appRole.appName
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

    /// The settings, as Instant Teacher's design lists them: Preferences,
    /// Language, Notifications and Privacy Controls. App Permissions is not
    /// among them, in either app: the profile holds those switches.
    var primarySettingsRows: [SettingsRow] {
        [
            SettingsRow(
                title: LocalizationSupport.localized("Preferences"),
                subtitle: role == .teacher
                    ? LocalizationSupport.localized("Availability on launch and currency")
                    : LocalizationSupport.localized("Default session type and currency"),
                systemImage: "slider.horizontal.3",
                iconColor: .primary,
                action: .appPreferences
            ),
            SettingsRow(
                title: LocalizationSupport.localized("Language"),
                subtitle: selectedLanguage.title,
                systemImage: "globe",
                iconColor: .primary,
                action: .language
            ),
            SettingsRow(
                title: LocalizationSupport.localized("Notifications"),
                systemImage: "bell",
                iconColor: .primary,
                action: .notifications
            ),
            SettingsRow(
                title: LocalizationSupport.localized("Privacy Controls"),
                systemImage: "shield",
                iconColor: .primary,
                action: .privacyControls
            )
        ]
    }

    /// The rest of the settings, which the design leaves out, in a card of the
    /// same style: the money — a student's payments, a teacher's payouts — the
    /// about pages, and the account, whose Log Out and Delete Account must
    /// stay within reach. The icons are symbols SkipUI draws on Android too.
    var moreSettingsRows: [SettingsRow] {
        var rows = [
            role == .teacher
                ? SettingsRow(
                    title: LocalizationSupport.localized("Teacher Payout Settings"),
                    subtitle: LocalizationSupport.localized("Choose where your monthly payout is sent"),
                    systemImage: "banknote",
                    iconColor: .primary,
                    action: .teacherPayouts
                )
                : SettingsRow(
                    title: LocalizationSupport.localized("Payment History"),
                    subtitle: LocalizationSupport.localized("View your lesson payment history"),
                    systemImage: "cart",
                    iconColor: .primary,
                    action: .studentPayments
                ),
            SettingsRow(
                title: LocalizationSupport.localized("About"),
                systemImage: "info.circle",
                iconColor: .primary,
                action: .about
            ),
            SettingsRow(
                title: LocalizationSupport.localized("Account & Security"),
                subtitle: LocalizationSupport.localized("Password, logout and account removal"),
                systemImage: "lock",
                iconColor: .primary,
                action: .accountSecurity
            )
        ]

        #if DEBUG
//        rows.append(
//            SettingsRow(
//                title: LocalizationSupport.localized("Force Reload Remote Config"),
//                subtitle: LocalizationSupport.localized("Debug builds only"),
//                systemImage: "arrow.clockwise.circle",
//                iconColor: .primary,
//                action: .forceReloadRemoteConfig
//            )
//        )
//        rows.append(
//            SettingsRow(
//                title: LocalizationSupport.localized("Test Crashlytics Crash"),
//                subtitle: LocalizationSupport.localized("Debug builds only"),
//                systemImage: "exclamationmark.triangle",
//                iconColor: .red,
//                isDestructive: true,
//                action: .testCrashlyticsCrash
//            )
//        )
        #endif

        return rows
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
