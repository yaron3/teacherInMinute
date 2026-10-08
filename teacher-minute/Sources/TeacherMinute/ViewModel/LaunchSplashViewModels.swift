//
//  LaunchSplashViewModels.swift
//  teacher-minute
//
//  The launch splash holds no state of its own, but its copy still belongs in
//  a view model rather than in the view, like every other screen's. Each app
//  speaks to its own audience: the student app promises help, the teacher app
//  calls its teachers to work.
//

import Foundation
import Observation
import SkipFuse

/// The splash's three-part tagline: a question, then a highlighted phrase that
/// `promise` completes.
@MainActor
protocol LaunchSplashViewModeling: AnyObject {
  var question: String { get }
  var highlight: String { get }
  var promise: String { get }
}

/// The view model for the app this build is.
@MainActor
func makeLaunchSplashViewModel() -> any LaunchSplashViewModeling {
  AuthRole.appRole == .teacher ? LaunchSplashTeacherViewModel() : LaunchSplashStudentViewModel()
}

@Observable
@MainActor
final class LaunchSplashStudentViewModel: LaunchSplashViewModeling {
  var question: String { LocalizationSupport.localized("Stuck?") }
  var highlight: String { LocalizationSupport.localized("A human teacher") }
  var promise: String { LocalizationSupport.localized("within 90 seconds") }
}

@Observable
@MainActor
final class LaunchSplashTeacherViewModel: LaunchSplashViewModeling {
  var question: String { LocalizationSupport.localized("Available?") }
  var highlight: String { LocalizationSupport.localized("Students are waiting") }
  var promise: String { LocalizationSupport.localized("Answer quickly") }
}
