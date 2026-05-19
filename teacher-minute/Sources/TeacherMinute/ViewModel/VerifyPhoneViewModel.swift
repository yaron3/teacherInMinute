//
//  VerifyPhoneViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import SwiftUI
import Observation

@Observable
@MainActor
final class VerifyPhoneViewModel {
    var phoneNumber = "+1 (555) 000-0000"
    var digits = Array(repeating: "", count: 4)

    var onVerified: (() -> Void)?

    var code: String { digits.joined() }

    var canVerify: Bool { code.count == 4 }

    func verify() {
        guard canVerify else { return }
        AnalyticsService.shared.logEvent(AnalyticsEvent.phoneVerified)
        onVerified?()
    }

    func resendCode() {
        AnalyticsService.shared.logEvent(AnalyticsEvent.phoneVerifySent, parameters: ["context": "resend"])
        // TODO: resend SMS
    }

    func changeContactInfo() {
        // TODO: navigate back to edit phone
    }

    func contactSupport() {
        // TODO: open support
    }
}
