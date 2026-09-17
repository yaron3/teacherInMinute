//
//  EmailRewardViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the verify-your-email reward banner and its dialogs.
//

import Foundation

extension EmailRewardViewModel {
  var verifyEmailTitle: String { LocalizationSupport.localized("Verify your email") }
  var resendLabel: String { LocalizationSupport.localized("Resend email") }
  var checkVerificationLabel: String { LocalizationSupport.localized("I've verified") }
  var emailSentTitle: String { LocalizationSupport.localized("Email sent") }
  var linkSentFormat: String {
    LocalizationSupport.localized("We sent a link to %@. Open it, then come back and tap \u{201C}I've verified\u{201D}.")
  }
  var sendFailedMessage: String {
    LocalizationSupport.localized("Couldn't send the email. Please try again later.")
  }
  var checkFailedMessage: String {
    LocalizationSupport.localized("Couldn't check your email right now. Please try again.")
  }
  var notVerifiedTitle: String { LocalizationSupport.localized("Not verified yet") }
  var notVerifiedMessage: String {
    LocalizationSupport.localized("Open the link we emailed you, then tap \u{201C}I've verified\u{201D} again.")
  }
  var alreadyClaimedMessage: String {
    LocalizationSupport.localized("This email address has already received its welcome reward.")
  }
  var teacherGrantedTitle: String { LocalizationSupport.localized("Welcome bonus unlocked") }
  var teacherBonusTitle: String { LocalizationSupport.localized("Welcome bonus") }
  var studentGrantedMessage: String {
    LocalizationSupport.localized("Thanks for verifying your email. Enjoy your first lessons!")
  }
  var okLabel: String { LocalizationSupport.localized("OK") }

  func studentGrantedTitle(minutes: Int) -> String {
    String(format: LocalizationSupport.localized("%d free minutes added"), minutes)
  }

  func studentOfferText(minutes: Int) -> String {
    String(format: LocalizationSupport.localized("Verify your email address and get %d free minutes."), minutes)
  }

  func teacherOfferText(percent: Int, minutes: Int) -> String {
    String(
      format: LocalizationSupport.localized("Verify your email address and keep %d%% of your earnings for your first %d minutes of teaching."),
      percent,
      minutes
    )
  }

  func teacherBonusText(percent: Int, minutes: Int) -> String {
    String(
      format: LocalizationSupport.localized("You keep %d%% of your earnings for your next %d minutes of teaching."),
      percent,
      minutes
    )
  }
}
