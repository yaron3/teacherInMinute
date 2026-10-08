//
//  VerifyEmailViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the verify-your-email step of a student's sign-up. Most of it is
//  shared, word for word, with the home screen's verify banner.
//

import Foundation

extension VerifyEmailViewModel {
  var verifyEmailTitle: String { LocalizationSupport.localized("Verify your email") }
  var linkSentToText: String { LocalizationSupport.localized("We sent a verification link to") }
  var tapLinkHint: String {
    LocalizationSupport.localized("Tap the link in the email on this phone. It brings you straight back to the app.")
  }
  var changeContactInfoLabel: String { LocalizationSupport.localized("Change email or phone") }
  var resendLabel: String { LocalizationSupport.localized("Resend email") }
  var notNowLabel: String { LocalizationSupport.localized("Not now") }
  var backLabel: String { LocalizationSupport.localized("Back") }
  var okLabel: String { LocalizationSupport.localized("OK") }

  var emailSentTitle: String { LocalizationSupport.localized("Email sent") }
  var linkSentMessage: String {
    String(
      format: LocalizationSupport.localized("We sent a new link to %@. Tap it on this phone to finish."),
      email
    )
  }
  var sendFailedMessage: String {
    LocalizationSupport.localized("Couldn't send the email. Please try again later.")
  }
  var emailChangedTitle: String { LocalizationSupport.localized("Email address changed") }
  var logInAgainMessage: String {
    LocalizationSupport.localized("Please log in again with your new email address.")
  }
  var emailVerifiedTitle: String { LocalizationSupport.localized("Email verified") }
  var promotionEndedMessage: String {
    LocalizationSupport.localized("Thanks for verifying your email. The free-minutes promotion has ended.")
  }
  var grantedMessage: String {
    LocalizationSupport.localized("Thanks for verifying your email. Enjoy your first lessons!")
  }

  /// The reward pitch, or nil while there is nothing to offer.
  var offerText: String? {
    guard rewardMinutes > 0 else { return nil }
    return String(format: LocalizationSupport.localized("Verify your email address and get %d free minutes."), rewardMinutes)
  }

  func grantedTitle(minutes: Int) -> String {
    String(format: LocalizationSupport.localized("%d free minutes added"), minutes)
  }
}

extension VerifyEmailViewModel: OnboardingBackViewModeling {}
