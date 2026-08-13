//
//  CreditCardEntry.swift
//  teacher-minute
//
//  Formatting and validation for the in-app credit-card form. Kept out of the
//  view so the rules (brand detection, Luhn, expiry) are testable and shared by
//  iOS and Android.
//

import Foundation

// MARK: - Brand

/// Card brands the form needs to tell apart — the ones whose digit grouping,
/// length, or CVV length differs. Everything else falls back to `unknown`,
/// which uses the common 4-4-4-4 / 3-digit-CVV shape.
enum CreditCardBrand {
  case visa
  case mastercard
  case amex
  case discover
  case dinersClub
  case jcb
  case unknown

  /// Longest accepted number, so typing stops at a sensible point per brand.
  var maxDigits: Int {
    switch self {
    case .amex:       return 15
    case .dinersClub: return 14
    default:          return 19
    }
  }

  /// Digit counts between the spaces shown in the number field.
  var digitGroups: [Int] {
    switch self {
    case .amex:       return [4, 6, 5]
    case .dinersClub: return [4, 6, 4]
    default:          return [4, 4, 4, 4, 3]
    }
  }

  var cvvLength: Int {
    self == .amex ? 4 : 3
  }

  /// Shortest valid number for the brand — a 16-digit Visa and a 13-digit Visa
  /// are both legal, so this is a floor rather than an exact length.
  var minDigits: Int {
    switch self {
    case .amex:       return 15
    case .dinersClub: return 14
    case .visa:       return 13
    default:          return 16
    }
  }

  static func detect(number digits: String) -> CreditCardBrand {
    guard let first = digits.first else { return .unknown }
    let twoDigitPrefix = Int(String(digits.prefix(2))) ?? 0
    let fourDigitPrefix = Int(String(digits.prefix(4))) ?? 0

    if first == "4" { return .visa }
    if (51...55).contains(twoDigitPrefix) { return .mastercard }
    if (2221...2720).contains(fourDigitPrefix) { return .mastercard }
    if twoDigitPrefix == 34 || twoDigitPrefix == 37 { return .amex }
    if fourDigitPrefix == 6011 || twoDigitPrefix == 65 { return .discover }
    if twoDigitPrefix == 36 || twoDigitPrefix == 38 || (300...305).contains(fourDigitPrefix / 10) {
      return .dinersClub
    }
    if (3528...3589).contains(fourDigitPrefix) { return .jcb }
    return .unknown
  }
}

// MARK: - Validation

enum CreditCardField {
  case number
  case expiry
  case cvv
  case name
}

// MARK: - Entry

/// The card form's typed state, in the exact shape the fields display it
/// (grouped number, "MM/YY" expiry). `cardDetails` converts it to the raw form
/// Braintree expects, and is `nil` until every field validates.
struct CreditCardEntry {
  var number = ""
  var expiry = ""
  var cvv = ""
  var cardholderName = ""

  var brand: CreditCardBrand {
    CreditCardBrand.detect(number: Self.digits(number))
  }

  // MARK: Formatting

  /// Re-formats what the buyer typed into the number field: digits only, capped
  /// at the brand's length, spaced into the brand's groups.
  static func formatNumber(_ raw: String) -> String {
    let brand = CreditCardBrand.detect(number: digits(raw))
    let capped = String(digits(raw).prefix(brand.maxDigits))
    return group(capped, sizes: brand.digitGroups)
  }

  /// Re-formats the expiry field as "MM/YY", normalizing a leading month digit
  /// above 1 (typing "5" gives "05"). The slash only appears once a year digit
  /// is typed: a trailing "05/" would be re-added the moment the buyer
  /// backspaced over it, making the month impossible to correct.
  static func formatExpiry(_ raw: String) -> String {
    var typed = digits(raw)
    if let first = typed.first, let firstValue = first.wholeNumberValue, firstValue > 1 {
      typed = "0" + typed
    }
    let capped = String(typed.prefix(4))
    if capped.count <= 2 { return capped }
    let month = String(capped.prefix(2))
    let year = String(capped.dropFirst(2))
    return "\(month)/\(year)"
  }

  static func formatCVV(_ raw: String, brand: CreditCardBrand) -> String {
    String(digits(raw).prefix(brand.cvvLength))
  }

  static func digits(_ value: String) -> String {
    String(value.filter { $0.isNumber })
  }

  static func group(_ digits: String, sizes: [Int]) -> String {
    let characters = Array(digits)
    var grouped = ""
    var index = 0
    var groupIndex = 0
    while index < characters.count {
      let size = groupIndex < sizes.count ? sizes[groupIndex] : 4
      if index > 0 { grouped += " " }
      let end = min(index + size, characters.count)
      for position in index..<end {
        grouped.append(characters[position])
      }
      index = end
      groupIndex += 1
    }
    return grouped
  }

  // MARK: Validation

  /// The first field that is filled in but wrong, or `nil` when nothing typed
  /// so far is invalid. Empty fields don't count — that's `isComplete`'s job —
  /// so the buyer isn't shown an error while still typing the first field.
  var invalidField: CreditCardField? {
    let numberDigits = Self.digits(number)
    if numberDigits.count >= brand.minDigits, !Self.passesLuhn(numberDigits) {
      return .number
    }
    if Self.digits(expiry).count == 4, Self.expiryComponents(expiry) == nil {
      return .expiry
    }
    return nil
  }

  var isComplete: Bool {
    let numberDigits = Self.digits(number)
    return numberDigits.count >= brand.minDigits
      && Self.passesLuhn(numberDigits)
      && Self.expiryComponents(expiry) != nil
      && cvv.count == brand.cvvLength
      && !cardholderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// Braintree-ready details, or `nil` while the entry is incomplete/invalid.
  var cardDetails: CardDetails? {
    guard isComplete, let expiry = Self.expiryComponents(expiry) else { return nil }
    return CardDetails(
      number: Self.digits(number),
      expirationMonth: expiry.month,
      expirationYear: expiry.year,
      cvv: cvv,
      cardholderName: cardholderName.trimmingCharacters(in: .whitespacesAndNewlines),
      postalCode: ""
    )
  }

  /// Splits "MM/YY" into the two-digit month and four-digit year Braintree
  /// wants, returning `nil` when the month is out of range or the card has
  /// already expired (a card is valid through the last day of its month).
  static func expiryComponents(_ expiry: String) -> (month: String, year: String)? {
    let typed = digits(expiry)
    guard typed.count == 4 else { return nil }
    guard let month = Int(String(typed.prefix(2))), (1...12).contains(month) else { return nil }
    guard let shortYear = Int(String(typed.dropFirst(2))) else { return nil }

    let calendar = Calendar.current
    let now = Date()
    let currentYear = calendar.component(.year, from: now)
    let currentMonth = calendar.component(.month, from: now)
    let century = (currentYear / 100) * 100
    let year = century + shortYear

    if year < currentYear { return nil }
    if year == currentYear, month < currentMonth { return nil }

    return (month: String(format: "%02d", month), year: String(year))
  }

  static func passesLuhn(_ digits: String) -> Bool {
    guard digits.count >= 12 else { return false }
    var sum = 0
    var isSecondDigit = false
    for character in Array(digits).reversed() {
      guard let digit = character.wholeNumberValue else { return false }
      if isSecondDigit {
        let doubled = digit * 2
        sum += doubled > 9 ? doubled - 9 : doubled
      } else {
        sum += digit
      }
      isSecondDigit = !isSecondDigit
    }
    return sum % 10 == 0
  }
}
