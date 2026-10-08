//
//  EmailVerificationLinkViewModel.swift
//  teacher-minute
//
//  The app's side of the verification email's link. The backend has already
//  verified the address and claimed the welcome reward by the time the link
//  opens the app (functions/src/emailVerification.ts); the URL only carries the
//  outcome, which is said in a dialog over whatever screen is up:
//
//    <scheme>://email-verified?status=granted&minutes=30
//    <scheme>://email-verified?status=promotion_ended
//

import Foundation
import Observation

@MainActor
@Observable
final class EmailVerificationLinkViewModel {
  static let shared = EmailVerificationLinkViewModel()

  enum Outcome: String {
    case granted
    case promotionEnded = "promotion_ended"
    case alreadyGranted = "already_granted"
    case claimedByOtherAccount = "claimed_by_other_account"
    case verified
    case emailInUse = "email_in_use"
    case expired
    case invalid
    case error

    /// The address is verified, whatever happened to the reward.
    var verifiesEmail: Bool {
      switch self {
      case .granted, .promotionEnded, .alreadyGranted, .claimedByOtherAccount, .verified:
        return true
      case .emailInUse, .expired, .invalid, .error:
        return false
      }
    }
  }

  var dialog: EmailRewardDialog?
  /// Bumped each time a link verified the address, so the verify step can move
  /// on and a home screen can re-read the balance.
  var verifiedVersion = 0

  private init() {}

  /// Takes the URL when it is a verification result, and says whether it was.
  func handle(url: URL) -> Bool {
    guard url.host == "email-verified" else { return false }
    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    func number(_ name: String) -> Int { Int(value(name) ?? "") ?? 0 }

    let outcome = Outcome(rawValue: value("status") ?? "") ?? .error
    logger.info("[EmailVerificationLink] outcome=\(outcome.rawValue)")
    AnalyticsService.shared.logEvent(AnalyticsEvent.emailVerifyLinkOpened, parameters: ["status": outcome.rawValue])

    dialog = dialog(for: outcome, minutes: number("minutes"), percent: number("percent"), bonusMinutes: number("bonusMinutes"))
    if outcome.verifiesEmail {
      verifiedVersion += 1
    }
    return true
  }

  func dismissDialog() {
    dialog = nil
  }

  func dialog(for outcome: Outcome, minutes: Int, percent: Int, bonusMinutes: Int) -> EmailRewardDialog {
    switch outcome {
    case .granted where percent > 0:
      return EmailRewardDialog(title: teacherGrantedTitle, message: teacherBonusText(percent: percent, minutes: bonusMinutes))
    case .granted:
      return EmailRewardDialog(title: studentGrantedTitle(minutes: minutes), message: studentGrantedMessage)
    case .promotionEnded:
      return EmailRewardDialog(title: emailVerifiedTitle, message: promotionEndedMessage)
    case .alreadyGranted:
      return EmailRewardDialog(title: emailVerifiedTitle, message: alreadyGrantedMessage)
    case .claimedByOtherAccount:
      return EmailRewardDialog(title: emailVerifiedTitle, message: alreadyClaimedMessage)
    case .verified:
      return EmailRewardDialog(title: emailVerifiedTitle, message: thanksForVerifyingMessage)
    case .emailInUse:
      return EmailRewardDialog(title: emailInUseTitle, message: emailInUseMessage)
    case .expired:
      return EmailRewardDialog(title: linkExpiredTitle, message: linkExpiredMessage)
    case .invalid:
      return EmailRewardDialog(title: linkInvalidTitle, message: linkInvalidMessage)
    case .error:
      return EmailRewardDialog(title: verifyFailedTitle, message: verifyFailedMessage)
    }
  }
}
