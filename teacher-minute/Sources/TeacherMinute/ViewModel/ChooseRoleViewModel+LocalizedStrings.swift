//
//  ChooseRoleViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the role-selection onboarding step.
//

import Foundation

extension ChooseRoleViewModel {

    // MARK: Screen chrome
    var screenTitle: String { LocalizationSupport.localized("Choose Your Role") }
    var subtitleText: String { LocalizationSupport.localized("Choose your role") }
    var continueLabel: String { LocalizationSupport.localized("Continue") }
    var okLabel: String { LocalizationSupport.localized("OK") }

    // MARK: Role cards
    var studentRoleTitle: String { LocalizationSupport.localized("I am a Student") }
    var studentRoleBullets: [String] {
        [LocalizationSupport.localized("On-demand help"),
         LocalizationSupport.localized("Per-minute billing")]
    }
    var teacherRoleTitle: String { LocalizationSupport.localized("I am a Teacher") }
    var teacherRoleBullets: [String] {
        [LocalizationSupport.localized("Earn while teaching"),
         LocalizationSupport.localized("Verification required")]
    }

    // MARK: Legal documents
    var eulaTitle: String { LocalizationSupport.localized("EULA") }
    var privacyPolicyTitle: String { LocalizationSupport.localized("Privacy Policy") }
}
