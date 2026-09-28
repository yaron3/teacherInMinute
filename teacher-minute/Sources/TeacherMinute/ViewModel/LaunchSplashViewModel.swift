//
//  LaunchSplashViewModel.swift
//  teacher-minute
//
//  The launch splash holds no state of its own, but its copy still belongs in
//  a view model rather than in the view, like every other screen's.
//

import Foundation
import Observation
import SkipFuse

@Observable
@MainActor
final class LaunchSplashViewModel {
  var stuckQuestion: String { LocalizationSupport.localized("Stuck?") }

  /// The highlighted start of the tagline's second line, which
  /// `responseTimePromise` completes.
  var humanTeacherHighlight: String { LocalizationSupport.localized("A human teacher") }
  var responseTimePromise: String { LocalizationSupport.localized("within 90 seconds") }
}
