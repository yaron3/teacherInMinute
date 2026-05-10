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
    let action: SettingsAction
}

enum SettingsAction: Equatable {
    case changePassword
    case logOut
    case deleteAccount
    case teacherPayouts
    case studentPayments
    case notifications
    case privacy
    case about
}

enum SettingsSheet: Identifiable {
    case about(URL)
    
    var id: String {
        switch self {
        case .about(let url):
            return "about-\(url.absoluteString)"
        }
    }
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
@MainActor
final class SettingsViewModel {
    let appVersion = "Math Connect App v2.4.1"
    
    var activeSheet: SettingsSheet?
    var showDeleteAccountConfirmation = false
    var showAlert = false
    var alertTitle = "Settings"
    var alertMessage: String?
    var isLoading = false
    
    private let authService = AuthService()
    private let remoteConfigService: SettingsRemoteConfigService
    
    init(remoteConfigService: SettingsRemoteConfigService = .shared) {
        self.remoteConfigService = remoteConfigService
    }

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
                        isDestructive: false,
                        action: .changePassword
                    ),
                    SettingsRow(
                        title: "Log Out",
                        subtitle: nil,
                        systemImage: "rectangle.portrait.and.arrow.right",
                        iconColor: .red,
                        isDestructive: true,
                        action: .logOut
                    ),
                    SettingsRow(
                        title: "Delete Account",
                        subtitle: "Permanently remove your account",
                        systemImage: "trash.fill",
                        iconColor: .red,
                        isDestructive: true,
                        action: .deleteAccount
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
                        isDestructive: false,
                        action: .teacherPayouts
                    ),
                    SettingsRow(
                        title: "Student Payment Methods",
                        subtitle: "Cards & billing history",
                        systemImage: "creditcard.fill",
                        iconColor: .pink,
                        isDestructive: false,
                        action: .studentPayments
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
                        isDestructive: false,
                        action: .notifications
                    ),
                    SettingsRow(
                        title: "Privacy Controls",
                        subtitle: nil,
                        systemImage: "shield.lefthalf.filled",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .privacy
                    )
                ]
            ),
            SettingsSection(
                title: "ABOUT",
                rows: [
                    SettingsRow(
                        title: "About",
                        subtitle: nil,
                        systemImage: "doc.text.fill",
                        iconColor: .primary,
                        isDestructive: false,
                        action: .about
                    )
                ]
            )
        ]
    }

    func select(_ row: SettingsRow) {
        switch row.action {
        case .about:
            Task { await openAbout() }
        case .deleteAccount:
            showDeleteAccountConfirmation = true
        case .logOut:
            _ = logOut()
        default:
            present(message: "This setting is not available yet.")
        }
    }
    
    func deleteAccount() async -> Bool {
        guard let uid = authService.currentUserID else {
            present(message: SettingsError.missingUser.localizedDescription)
            return false
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await UserService.shared.deleteUserData(uid: uid)
            try await authService.deleteCurrentUser()
            return true
        } catch {
            present(
                title: "Delete Account",
                message: "\(error.localizedDescription) You may need to log in again before deleting your account."
            )
            return false
        }
    }
    
    func logOut() -> Bool {
        do {
            try authService.signOut()
            return true
        } catch {
            present(title: "Log Out", message: error.localizedDescription)
            return false
        }
    }
    
    private func openAbout() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            activeSheet = .about(try await remoteConfigService.fetchAboutURL())
        } catch {
            present(title: "About", message: error.localizedDescription)
        }
    }
    
    private func present(title: String = "Settings", message: String) {
        alertTitle = title
        alertMessage = message
        showAlert = true
    }
}
