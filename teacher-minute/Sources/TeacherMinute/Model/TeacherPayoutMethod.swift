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
      return !phone.trimmed.isEmpty
    case .paypal:
      // PayPal is saved by completing the login, not by typing — see
      // TeacherEarningsViewModel.connectPayPalPayoutAccount.
      return isPayPalVerified && !email.trimmed.isEmpty
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
      return ["type": type.rawValue, "phone": phone.trimmed]
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
