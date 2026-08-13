import Foundation
import Testing
@testable import TeacherMinute

struct CreditCardEntryTests {

  // Test numbers published by Braintree/the card networks — they pass Luhn but
  // are not real accounts.
  static let visa = "4111111111111111"
  static let mastercard = "5555555555554444"
  static let amex = "378282246310005"

  // MARK: - Brand detection

  @Test func detectsBrandsFromTheirPrefixes() {
    #expect(CreditCardBrand.detect(number: Self.visa) == .visa)
    #expect(CreditCardBrand.detect(number: Self.mastercard) == .mastercard)
    #expect(CreditCardBrand.detect(number: "2221000000000009") == .mastercard)
    #expect(CreditCardBrand.detect(number: Self.amex) == .amex)
    #expect(CreditCardBrand.detect(number: "6011111111111117") == .discover)
    #expect(CreditCardBrand.detect(number: "3530111333300000") == .jcb)
    #expect(CreditCardBrand.detect(number: "") == .unknown)
  }

  @Test func amexUsesAFourDigitCVV() {
    #expect(CreditCardBrand.amex.cvvLength == 4)
    #expect(CreditCardBrand.visa.cvvLength == 3)
  }

  // MARK: - Formatting

  @Test func formatsNumberIntoBrandGroups() {
    #expect(CreditCardEntry.formatNumber(Self.visa) == "4111 1111 1111 1111")
    #expect(CreditCardEntry.formatNumber(Self.amex) == "3782 822463 10005")
  }

  @Test func formatNumberStripsNonDigitsAndCapsAtBrandLength() {
    #expect(CreditCardEntry.formatNumber("4111-1111 1111a1111") == "4111 1111 1111 1111")
    // Amex tops out at 15 digits, so the trailing digits are dropped.
    #expect(CreditCardEntry.formatNumber(Self.amex + "999") == "3782 822463 10005")
  }

  @Test func formatsExpiryAsMonthSlashYear() {
    #expect(CreditCardEntry.formatExpiry("12") == "12")
    #expect(CreditCardEntry.formatExpiry("1230") == "12/30")
    #expect(CreditCardEntry.formatExpiry("12/30") == "12/30")
    // A leading digit that can't start a month is read as the month itself.
    #expect(CreditCardEntry.formatExpiry("5") == "05")
    // Backspacing over the slash has to leave the month editable, so the slash
    // is only added once there is a year digit behind it.
    #expect(CreditCardEntry.formatExpiry("12") == "12")
    #expect(CreditCardEntry.formatExpiry("123") == "12/3")
  }

  @Test func formatCVVRespectsBrandLength() {
    #expect(CreditCardEntry.formatCVV("12345", brand: .visa) == "123")
    #expect(CreditCardEntry.formatCVV("12345", brand: .amex) == "1234")
    #expect(CreditCardEntry.formatCVV("1a2b3", brand: .visa) == "123")
  }

  // MARK: - Luhn

  @Test func luhnAcceptsValidNumbersAndRejectsTypos() {
    #expect(CreditCardEntry.passesLuhn(Self.visa))
    #expect(CreditCardEntry.passesLuhn(Self.mastercard))
    #expect(CreditCardEntry.passesLuhn(Self.amex))
    #expect(!CreditCardEntry.passesLuhn("4111111111111112"))
    #expect(!CreditCardEntry.passesLuhn("1234"))
  }

  // MARK: - Expiry

  @Test func expiryRejectsBadMonthsAndPastDates() {
    #expect(CreditCardEntry.expiryComponents("13/30") == nil)
    #expect(CreditCardEntry.expiryComponents("00/30") == nil)
    #expect(CreditCardEntry.expiryComponents("12/2") == nil)
    #expect(CreditCardEntry.expiryComponents("01/20") == nil)
  }

  @Test func expiryExpandsTwoDigitYearsToFour() {
    let year = Calendar.current.component(.year, from: Date()) + 3
    let shortYear = String(year % 100)
    let parsed = CreditCardEntry.expiryComponents("07/\(shortYear)")
    #expect(parsed?.month == "07")
    #expect(parsed?.year == String(year))
  }

  @Test func cardIsValidThroughTheEndOfItsExpiryMonth() {
    let now = Date()
    let month = Calendar.current.component(.month, from: now)
    let year = Calendar.current.component(.year, from: now)
    let expiry = String(format: "%02d%02d", month, year % 100)
    #expect(CreditCardEntry.expiryComponents(expiry) != nil)
  }

  // MARK: - Entry validation

  @Test func entryIsCompleteOnlyWhenEveryFieldValidates() {
    var entry = CreditCardEntry()
    #expect(!entry.isComplete)

    entry.number = CreditCardEntry.formatNumber(Self.visa)
    entry.expiry = futureExpiry()
    entry.cvv = "123"
    #expect(!entry.isComplete)  // no cardholder name yet

    entry.cardholderName = "Ada Lovelace"
    #expect(entry.isComplete)
  }

  @Test func entryFlagsAFullButInvalidNumber() {
    var entry = CreditCardEntry()
    entry.number = CreditCardEntry.formatNumber("4111111111111112")
    #expect(entry.invalidField == .number)

    // A half-typed number is not an error yet.
    entry.number = "4111 11"
    #expect(entry.invalidField == nil)
  }

  @Test func entryFlagsAnExpiredCard() {
    var entry = CreditCardEntry()
    entry.expiry = "01/20"
    #expect(entry.invalidField == .expiry)
  }

  @Test func cardDetailsStripFormattingForBraintree() {
    var entry = CreditCardEntry()
    entry.number = CreditCardEntry.formatNumber(Self.visa)
    entry.expiry = futureExpiry()
    entry.cvv = "123"
    entry.cardholderName = "  Ada Lovelace  "

    let details = entry.cardDetails
    #expect(details?.number == Self.visa)
    #expect(details?.expirationMonth == "07")
    #expect(details?.cardholderName == "Ada Lovelace")
  }

  @Test func cardDetailsAreNilWhileIncomplete() {
    var entry = CreditCardEntry()
    entry.number = CreditCardEntry.formatNumber(Self.visa)
    #expect(entry.cardDetails == nil)
  }

  func futureExpiry() -> String {
    let year = Calendar.current.component(.year, from: Date()) + 3
    return CreditCardEntry.formatExpiry(String(format: "07%02d", year % 100))
  }
}
