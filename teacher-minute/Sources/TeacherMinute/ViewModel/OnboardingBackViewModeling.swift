//
//  OnboardingBackViewModeling.swift
//  teacher-minute
//
//  Backing out of the first onboarding step signs the user out, so every
//  onboarding screen confirms it first. The screens have different view
//  models, so the confirmation's copy is defined here once.
//

import Foundation

protocol OnboardingBackViewModeling: AnyObject {}

extension OnboardingBackViewModeling {
    var onboardingBackTitle: String { LocalizationSupport.localized("Log out?") }
    var onboardingBackMessage: String {
        LocalizationSupport.localized("Going back from here returns you to the sign-in screen and signs you out.")
    }
    var onboardingBackCancelLabel: String { LocalizationSupport.localized("Cancel") }
    var onboardingBackConfirmLabel: String { LocalizationSupport.localized("Log Out") }
}

extension ChooseRoleViewModel: OnboardingBackViewModeling {}
extension TeacherSubjectsViewModel: OnboardingBackViewModeling {}
extension TeacherIdentityVerificationViewModel: OnboardingBackViewModeling {}
extension CompleteProfileViewModel: OnboardingBackViewModeling {}
extension PermissionsSetupViewModel: OnboardingBackViewModeling {}
