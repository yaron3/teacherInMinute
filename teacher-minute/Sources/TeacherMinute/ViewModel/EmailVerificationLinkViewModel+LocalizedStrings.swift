//
//  EmailVerificationLinkViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the dialog the verification link opens the app with. The reward
//  lines are shared, word for word, with the verify banner's dialogs.
//

import Foundation

extension EmailVerificationLinkViewModel {
  var okLabel: String { LocalizationSupport.localized("OK") }

  var emailVerifiedTitle: String { LocalizationSupport.localized("Email verified") }
  var thanksForVerifyingMessage: String { LocalizationSupport.localized("Thanks for verifying your email.") }
  var promotionEndedMessage: String {
    LocalizationSupport.localized("Thanks for verifying your email. The free-minutes promotion has ended.")
  }
  var alreadyGrantedMessage: String {
    LocalizationSupport.localized("Your welcome reward was already added to your account.")
  }
  var alreadyClaimedMessage: String {
    LocalizationSupport.localized("This email address has already received its welcome reward.")
  }
  var studentGrantedMessage: String {
    LocalizationSupport.localized("Thanks for verifying your email. Enjoy your first lessons!")
  }
  var teacherGrantedTitle: String { LocalizationSupport.localized("Welcome bonus unlocked") }

  var emailInUseTitle: String { LocalizationSupport.localized("Email address in use") }
  var emailInUseMessage: String { LocalizationSupport.localized("Another account already uses this email address.") }
  var linkExpiredTitle: String { LocalizationSupport.localized("Link expired") }
  var linkExpiredMessage: String {
    LocalizationSupport.localized("This verification link has expired. Ask for a new one in the app.")
  }
  var linkInvalidTitle: String { LocalizationSupport.localized("Link not valid") }
  var linkInvalidMessage: String {
    LocalizationSupport.localized("This verification link is not valid. Ask for a new one in the app.")
  }
  var verifyFailedTitle: String { LocalizationSupport.localized("Couldn't verify your email") }
  var verifyFailedMessage: String { LocalizationSupport.localized("Something went wrong. Please try again later.") }

  func studentGrantedTitle(minutes: Int) -> String {
    String(format: LocalizationSupport.localized("%d free minutes added"), minutes)
  }

  func teacherBonusText(percent: Int, minutes: Int) -> String {
    String(
      format: LocalizationSupport.localized("You keep %d%% of your earnings for your next %d minutes of teaching."),
      percent,
      minutes
    )
  }
}
