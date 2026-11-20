//
//  OnboardingBackViewModeling.swift
//  teacher-minute
//
//  The onboarding steps share their back button's name. The screens have
//  different view models, so the copy is defined here once.
//

import Foundation

protocol OnboardingBackViewModeling: AnyObject {}

extension OnboardingBackViewModeling {
    /// The name of the back button in a step's header.
    var onboardingBackLabel: String { LocalizationSupport.localized("Back") }
}

extension TeacherSubjectsViewModel: OnboardingBackViewModeling {}
extension TeacherIdentityVerificationViewModel: OnboardingBackViewModeling {}
extension CompleteProfileViewModel: OnboardingBackViewModeling {}
extension PermissionsSetupViewModel: OnboardingBackViewModeling {}
