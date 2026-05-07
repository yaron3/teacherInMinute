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
}
