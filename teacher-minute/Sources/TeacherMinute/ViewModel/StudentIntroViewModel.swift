//
//  StudentIntroViewModel.swift
//  teacher-minute
//
//  The first screen a signed-out student sees in Instant Teacher. Its one
//  action starts them without an account — an anonymous session and a student
//  profile — and takes them straight to the home screen. Students who already
//  have an account log in from the home screen's menu.
//

import Foundation
import Observation
import SkipFuse

@Observable
@MainActor
final class StudentIntroViewModel {
  private(set) var isStarting = false
  /// Where the router goes once the student has started.
  private(set) var destination: OnboardingResume?
  var startErrorMessage: String?

  let authService = AuthService()

  var stuckQuestion: String { LocalizationSupport.localized("Stuck?") }
  /// The highlighted start of the headline's second line, which
  /// `responseTimePromise` completes.
  var humanTeacherHighlight: String { LocalizationSupport.localized("A human teacher") }
  var responseTimePromise: String { LocalizationSupport.localized("within 90 seconds") }
  var pitch: String {
    LocalizationSupport.localized("When AI can't explain it, we have a human teacher who sees exactly where you got stuck")
  }
  /// The welcome promotions, with the amounts the backend grants: the minutes
  /// for signing up (Remote Config `signup_reward_student_minutes` and
  /// `signup_reward_student_slots`) and for verifying the email
  /// (`email_reward_student_minutes` and `email_reward_student_slots`). Their
  /// minutes add up; the subscribers are the smaller cap, since only those
  /// get both. A reward set to 0 is left out, and the line with it while both
  /// are. A value not published yet falls back to the backend's own default
  /// (functions/src/signupRewards.ts and emailRewards.ts), so the line matches
  /// what is granted.
  var promotionText: String? {
    var signupMinutes = remoteConfigCount("signup_reward_student_minutes", default: 0)
    var signupSlots = remoteConfigCount("signup_reward_student_slots", default: 100)
    if signupMinutes == 0 || signupSlots == 0 {
      signupMinutes = 0
      signupSlots = Int.max
    }
    var verifyMinutes = remoteConfigCount("email_reward_student_minutes", default: 60)
    var verifySlots = remoteConfigCount("email_reward_student_slots", default: 100)
    if verifyMinutes == 0 || verifySlots == 0 {
      verifyMinutes = 0
      verifySlots = Int.max
    }
    let minutes = signupMinutes + verifyMinutes
    guard minutes > 0 else { return nil }
    let slots = min(signupSlots, verifySlots)
    return String(
      format: LocalizationSupport.localized("First %d minutes up to the next %d subscribers"),
      minutes,
      slots
    )
  }
  private func remoteConfigCount(_ key: String, default defaultValue: Int) -> Int {
    guard let value = Double(RemoteConfigService.shared.getString(key)) else { return defaultValue }
    return max(0, Int(value))
  }

  var startLabel: String { LocalizationSupport.localized("Get started") }
  var priceLine: String { LocalizationSupport.localized("₪2 per minute • no fixed lessons") }
  var startErrorTitle: String { LocalizationSupport.localized("Sign In Error") }
  var okLabel: String { LocalizationSupport.localized("OK") }

  func start() async {
    guard !isStarting else { return }
    isStarting = true
    defer { isStarting = false }

    let uid: String
    do {
      uid = try await authService.signInAnonymously()
    } catch {
      AnalyticsService.shared.logEvent(AnalyticsEvent.anonymousStartFailure, parameters: ["reason": error.localizedDescription])
      AnalyticsService.shared.recordError(error, context: "anonymousStart")
      startErrorMessage = localizedAuthErrorMessage(error)
      return
    }

    // The home screen does not need the profile to open, and the next launch
    // writes it again if it is missing (UserService.resumeRoute), so a failed
    // write is logged rather than stopping the student at the door.
    do {
      try await UserService.shared.saveAnonymousStudentProfile(uid: uid)
    } catch {
      logger.warning("[Intro] could not save the anonymous student profile: \(error)")
      AnalyticsService.shared.recordError(error, context: "anonymousStartProfile")
    }

    AnalyticsService.shared.setUser(uid: uid)
    AnalyticsService.shared.logEvent(AnalyticsEvent.anonymousStartSuccess)
    destination = .home(role: .student)
  }
}
