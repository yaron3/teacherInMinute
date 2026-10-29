//
//  MainTabViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the main screen's side menu.
//

import Foundation

extension MainTabViewModel {
    var openMenuLabel: String { LocalizationSupport.localized("Open menu") }
    var closeMenuLabel: String { LocalizationSupport.localized("Close menu") }
    var menuTitle: String { LocalizationSupport.localized("Menu") }
    var emailLabel: String { LocalizationSupport.localized("Email") }
    var phoneLabel: String { LocalizationSupport.localized("Phone") }
    var alreadyHaveAccountText: String { LocalizationSupport.localized("Already have an account?") }
    var logInLabel: String { LocalizationSupport.localized("Log In") }

    // MARK: Share

    var shareChoiceTitle: String { LocalizationSupport.localized("Share the App") }
    var shareChoiceMessage: String { LocalizationSupport.localized("What would you like to share?") }
    var cancelLabel: String { LocalizationSupport.localized("Cancel") }

    /// A choice's button. The apps go by their names in the app's language
    /// (see `AuthRole.localizedAppName`).
    func shareChoiceLabel(for target: ShareTarget) -> String {
        switch target {
        case .app(let role): role.localizedAppName
        case .website: LocalizationSupport.localized("Our Website")
        }
    }

    /// The icon on a choice's button: each app's own; none for the website.
    func shareChoiceIcon(for target: ShareTarget) -> String? {
        switch target {
        case .app(let role): role.appIconAsset
        case .website: nil
        }
    }

    /// What is shared: a line on what the link leads to, then the link.
    func shareText(for target: ShareTarget) -> String {
        let format = switch target {
        case .app(.student): LocalizationSupport.localized("Stuck on a question? Instant Teacher connects you to a real teacher in about a minute: %@")
        case .app(.teacher): LocalizationSupport.localized("Teach students live, whenever you are free, and get paid with Pro Teacher: %@")
        case .website: LocalizationSupport.localized("Meet Instant Teacher and Pro Teacher, live help from real teachers in about a minute: %@")
        }
        return String(format: format, target.url.absoluteString)
    }
}
