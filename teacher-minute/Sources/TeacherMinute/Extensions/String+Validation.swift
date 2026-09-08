//
//  String+Validation.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import Foundation

extension String {
    /// Returns true if the string looks like a valid e-mail address.
    var isEmail: Bool {
        let regex = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        return range(of: regex, options: .regularExpression) != nil
    }

    /// Returns true if the string contains only digits (e.g. a phone number).
    var isNumber: Bool {
        !isEmpty && allSatisfy { $0.isNumber }
    }

    /// An Israeli phone number in local, zero-prefixed digits ("0521234567"),
    /// or an empty string when the text is not one. A `+972` / `00972` country
    /// code is folded back to the local `0` form.
    ///
    /// The 9-or-10-digit shape it ends on is the one `requirePhone` in
    /// `functions/src/payoutMethod.ts` enforces when a teacher's Bit payout
    /// number is saved. That function is stricter about *spelling* — it strips
    /// only spaces and dashes — so store and send this normalized form rather
    /// than what was typed, and the two never disagree.
    var normalizedPhoneNumber: String {
        // Spacing, dashes, dots and parentheses carry no meaning and the
        // placeholder invites them; a letter or any other symbol means this is
        // not a phone number at all.
        var digits = ""
        for character in self where !" -().".contains(character) {
            digits.append(character)
        }
        if digits.hasPrefix("+") {
            digits = String(digits.dropFirst())
        } else if digits.hasPrefix("00") {
            digits = String(digits.dropFirst(2))
        }
        guard digits.allSatisfy({ "0123456789".contains($0) }) else {
            return ""
        }
        if digits.hasPrefix("972") {
            digits = "0" + digits.dropFirst(3)
        }
        guard digits.range(of: #"^0\d{8,9}$"#, options: .regularExpression) != nil else {
            return ""
        }
        return digits
    }

    /// Whether the string is a phone number the app and the backend will both
    /// accept. Empty strings are invalid — an optional field should check
    /// `isEmpty` first rather than asking this.
    var isValidPhoneNumber: Bool {
        !normalizedPhoneNumber.isEmpty
    }
}
