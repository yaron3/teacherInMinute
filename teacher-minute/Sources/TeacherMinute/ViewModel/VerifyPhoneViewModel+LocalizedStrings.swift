//
//  VerifyPhoneViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the phone-verification screen.
//

import Foundation

extension VerifyPhoneViewModel {
    var screenTitle: String { LocalizationSupport.localized("Verify your number") }
    var codeSentText: String { LocalizationSupport.localized("We've sent a 4-digit security code to") }
    var changeContactInfoLabel: String { LocalizationSupport.localized("Change contact info") }
    var resendCodeLabel: String { LocalizationSupport.localized("Resend Code Now") }
    var havingTroubleText: String { LocalizationSupport.localized("Having trouble?") }
    var contactSupportLabel: String { LocalizationSupport.localized("Contact Support") }
}
