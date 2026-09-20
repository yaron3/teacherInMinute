//
//  TeacherPayoutMethod.swift
//  teacher-minute
//
// Where a teacher's monthly payout is sent. Mirrors the shape validated and
// stored by the `updateTeacherPayoutMethod` backend callable
// (functions/src/payoutMethod.ts).

import Foundation

enum PayoutMethodType: String, CaseIterable, Identifiable {
  case bank
  case bit
  case paypal

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .bank:   return LocalizationSupport.localized("Bank Account")
    case .bit:    return LocalizationSupport.localized("Bit")
    case .paypal: return LocalizationSupport.localized("PayPal")
    }
  }

  var systemImage: String {
    switch self {
    case .bank:   return "building.columns.fill"
    case .bit:    return "phone.fill"
    case .paypal: return "envelope.fill"
    }
  }
}

/// A bank the backend will accept as a payout destination, from the list it
/// sends with the earnings summary — so the picker can never offer a bank that
/// `updateTeacherPayoutMethod` would reject.
struct PayoutBank: Identifiable {
  let code: String
  let name: String
  let nameHe: String

  var id: String { code }

  /// The bank's own name in the app's language. Bank names are proper nouns
  /// supplied by the backend, so they are not run through LocalizationSupport.
  var displayName: String {
    LocalizationSupport.currentLanguageCode == "he" ? nameHe : name
  }
}

/// One flat struct across all three method types — it doubles as the edit
/// form's state, so switching type in the form keeps whatever the teacher
/// already typed for the other ones until they save.
struct TeacherPayoutMethod {
  var type: PayoutMethodType = .bit

  // Bank transfer. The name is resolved from the code by the backend rather
  // than typed, so only the code is sent.
  var bankCode = ""
  var bankName = ""
  var branchNumber = ""
  var accountNumber = ""
  var accountHolderName = ""

  // Bit
  var phone = ""

  // PayPal
  var email = ""
  /// True only when the email came back from a completed PayPal login. The
  /// backend refuses to accept this from the client, so it is display-only here.
  var isPayPalVerified = false

  /// Whether the fields required for the selected type are filled in. The
  /// backend re-validates properly (format, length); this only gates the Save
  /// button so the teacher isn't sent to the server to be told a field is empty.
  var isComplete: Bool {
    switch type {
    case .bank:
      return !bankCode.trimmed.isEmpty
        && !branchNumber.trimmed.isEmpty
        && !accountNumber.trimmed.isEmpty
        && !accountHolderName.trimmed.isEmpty
    case .bit:
      // The one exception to "empty check only": `requirePhone` on the backend
      // rejects a malformed number outright, and the teacher can see that
      // before the round-trip.
      return phone.trimmed.isValidPhoneNumber
    case .paypal:
      // A well-formed address is enough to save. Signing in to PayPal
      // (connectPayPalPayoutAccount) additionally marks it confirmed, but is
      // not required: PayPal exposes no way to check an address for an
      // account, and a payout to an address without one is rejected at
      // transfer time.
      return email.trimmed.isEmail
    }
  }

  /// A short, non-sensitive description of where the money goes, mirroring the
  /// backend's `payoutMethodSummary` (functions/src/payoutMethod.ts) so a
  /// screen that reads the stored method directly renders it identically to one
  /// that gets the summary from the earnings service. Bank accounts never show
  /// more than their last 4 digits.
  var displaySummary: String {
    switch type {
    case .bank:
      let masked = "••••\(accountNumber.trimmed.suffix(4))"
      return bankName.trimmed.isEmpty ? masked : "\(bankName.trimmed) \(masked)"
    case .bit:
      return phone.trimmed
    case .paypal:
      return email.trimmed
    }
  }

  /// The payload for `updateTeacherPayoutMethod` — only the fields the chosen
  /// type actually uses, so a stale value from another type is never sent.
  var requestPayload: [String: Any] {
    switch type {
    case .bank:
      return [
        "type": type.rawValue,
        "bankCode": bankCode.trimmed,
        "branchNumber": branchNumber.trimmed,
        "accountNumber": accountNumber.trimmed,
        "accountHolderName": accountHolderName.trimmed,
      ]
    case .bit:
      // Sent in canonical local digits: `requirePhone` on the backend only
      // strips spaces and dashes, so parentheses from the placeholder's own
      // format ("+972 (52) 000-0000") would be rejected if forwarded as typed.
      return ["type": type.rawValue, "phone": phone.normalizedPhoneNumber]
    case .paypal:
      return ["type": type.rawValue, "email": email.trimmed]
    }
  }

  init() {}

  /// Rebuilds the method from the backend's stored copy. Returns `nil` when the
  /// teacher has not set one up yet.
  init?(data: [String: Any]) {
    guard let rawType = data["type"] as? String,
          let type = PayoutMethodType(rawValue: rawType)
    else { return nil }
    self.type = type
    bankCode = data["bankCode"] as? String ?? ""
    bankName = data["bankName"] as? String ?? ""
    branchNumber = data["branchNumber"] as? String ?? ""
    accountNumber = data["accountNumber"] as? String ?? ""
    accountHolderName = data["accountHolderName"] as? String ?? ""
    phone = data["phone"] as? String ?? ""
    email = data["email"] as? String ?? ""
    isPayPalVerified = data["verified"] as? Bool ?? false
  }
}

private extension String {
  var trimmed: String {
    trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
