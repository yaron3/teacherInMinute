//
//  TeacherEarningsViewModel.swift
//  teacher-minute
//

import SwiftUI
import Observation
import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

/// One calendar month of teacher earnings. Holds only numbers — every label is
/// derived from the viewer's locale below, so the same summary renders in
/// whichever language the app is set to.
struct MonthSummary: Identifiable {
    let id: String           // "yyyy-MM"
    let year: Int
    let month: Int           // 1-12
    let earningsCents: Int
    let minutesCount: Int
    let lessonCount: Int
    let isCurrentMonth: Bool
    let weeklyBreakdown: [WeekSummary]

    /// Month name alone, for the month picker chips.
    var shortName: String {
        LessonFormatting.monthName(month: month)
    }

    /// Month and year, marked when the month is still accruing.
    var displayName: String {
        let monthYear = LessonFormatting.monthYearText(year: year, month: month)
        guard isCurrentMonth else { return monthYear }
        return String(format: LocalizationSupport.localized("%@ (current)"), monthYear)
    }
}

struct WeekSummary: Identifiable {
    let id: String
    let index: Int
    let startDay: Int
    let endDay: Int
    let earningsCents: Int
    let minutesCount: Int
    let lessonCount: Int

    var label: String {
        String(format: LocalizationSupport.localized("Week %d (%d-%d)"), index, startDay, endDay)
    }
}

@Observable
@MainActor
final class TeacherEarningsViewModel {
    var months: [MonthSummary] = []
    var selectedMonthId: String = ""
    var totalEarningsCents: Int = 0
    var totalMonthsActive: Int = 0
    var currencyCode: String = LessonFormatting.defaultCurrencyCode
    var isLoading: Bool = false
    var errorMessage: String?

    /// The pending payout, from the backend's payout schedule: a month's
    /// earnings are paid on the 9th of the month after it (March is paid on
    /// 9 April). `nil` until the summary loads.
    var nextPaymentCents: Int = 0
    var nextPaymentDate: String = ""

    // MARK: - Payout method

    /// Where the payout is sent. `nil` until the teacher sets one up.
    var payoutMethod: TeacherPayoutMethod?
    /// Masked destination for display — the backend masks bank accounts to
    /// their last 4 digits, so the full number is never held here.
    var payoutMethodSummary: String = ""

    /// The form behind the Edit button. Seeded from `payoutMethod` when the
    /// sheet opens so the teacher edits what is currently on file.
    var payoutMethodDraft = TeacherPayoutMethod()
    var isEditingPayoutMethod = false
    var isSavingPayoutMethod = false
    var payoutMethodErrorMessage: String?

    /// The banks the backend will accept, for the form's picker.
    var banks: [PayoutBank] = []

    /// The phone number already on the teacher's profile, if any.
    var profilePhone: String = ""
    /// Set after saving a Bit number that differs from the profile, to ask
    /// whether the profile should be updated to match.
    var isOfferingProfilePhoneUpdate = false
    private var pendingProfilePhone = ""

    /// True while the PayPal login is on screen.
    var isConnectingPayPal = false

    var hasPayoutMethod: Bool { payoutMethod != nil }

    /// Whether the Bit form can offer the profile number instead of typing.
    var canUseProfilePhone: Bool {
        !profilePhone.isEmpty && payoutMethodDraft.phone.trimmingCharacters(in: .whitespacesAndNewlines) != profilePhone
    }

    func useProfilePhone() {
        payoutMethodDraft.phone = profilePhone
    }

    /// False once a load completes with no lessons on record, so the screen can
    /// say so rather than showing a wall of zeros.
    var hasEarningsData: Bool { !months.isEmpty }

    /// Only worth showing the payout card once there is a date to show.
    var hasPendingPayment: Bool { !nextPaymentDate.isEmpty }

    var currentMonthSummary: MonthSummary? {
        months.first(where: { $0.isCurrentMonth }) ?? months.last
    }

    var selectedMonth: MonthSummary? {
        months.first(where: { $0.id == selectedMonthId })
    }

    func formattedEarnings(_ cents: Int) -> String {
        LessonFormatting.currencyText(cents: cents, currencyCode: currencyCode)
    }

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task {
            await loadData()
            isLoading = false
        }
    }

    // MARK: - Private

    private func loadData() async {
        guard Auth.auth().currentUser != nil else {
            errorMessage = LocalizationSupport.localized("Could not load earnings.")
            return
        }

        do {
            let summary = try await FunctionsService.shared.teacherEarningsSummary()
            apply(summary)
            errorMessage = nil
        } catch {
            logger.error("[Earnings] failed loading summary: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "TeacherEarnings.summary")
            errorMessage = LocalizationSupport.localized("Could not load earnings.")
        }
    }

    private func apply(_ summary: TeacherEarningsSummaryResult) {
        currencyCode = summary.currency
        totalEarningsCents = summary.totalEarningsCents
        months = summary.months.map { month in
            MonthSummary(
                id: month.id,
                year: month.year,
                month: month.month,
                earningsCents: month.earningsCents,
                minutesCount: month.minutesCount,
                lessonCount: month.lessonCount,
                isCurrentMonth: month.isCurrentMonth,
                weeklyBreakdown: month.weeks.map { week in
                    WeekSummary(
                        id: "week-\(week.index)",
                        index: week.index,
                        startDay: week.startDay,
                        endDay: week.endDay,
                        earningsCents: week.earningsCents,
                        minutesCount: week.minutesCount,
                        lessonCount: week.lessonCount
                    )
                }
            )
        }
        totalMonthsActive = months.count
        selectedMonthId = months.first(where: { $0.isCurrentMonth })?.id ?? months.last?.id ?? ""

        if let payment = summary.nextPayment {
            nextPaymentCents = payment.amountCents
            nextPaymentDate = Self.payoutDateText(payment.payoutDate)
        } else {
            nextPaymentCents = 0
            nextPaymentDate = ""
        }

        payoutMethod = summary.payoutMethod
        payoutMethodSummary = summary.payoutMethodSummary
        banks = summary.banks
        profilePhone = summary.profilePhone
    }

    // MARK: - Editing the payout method

    func editPayoutMethod() {
        var draft = payoutMethod ?? TeacherPayoutMethod()
        // Starting fresh with a profile number already on file: pre-fill it, so
        // the common case is one tap rather than retyping.
        if payoutMethod == nil, !profilePhone.isEmpty {
            draft.phone = profilePhone
        }
        payoutMethodDraft = draft
        payoutMethodErrorMessage = nil
        isEditingPayoutMethod = true
    }

    func cancelPayoutMethodEditing() {
        isEditingPayoutMethod = false
        payoutMethodErrorMessage = nil
    }

    func savePayoutMethod() async {
        guard !isSavingPayoutMethod, payoutMethodDraft.isComplete else { return }
        isSavingPayoutMethod = true
        payoutMethodErrorMessage = nil
        defer { isSavingPayoutMethod = false }

        do {
            let summary = try await FunctionsService.shared.updateTeacherPayoutMethod(payoutMethodDraft)
            payoutMethod = payoutMethodDraft
            payoutMethodSummary = summary
            isEditingPayoutMethod = false
            logger.info("[Earnings] payout method saved type=\(self.payoutMethodDraft.type.rawValue)")

            // A Bit number the profile doesn't have yet is almost always the
            // teacher's own — offer to keep the profile in step rather than
            // silently holding two different numbers.
            let savedPhone = payoutMethodDraft.phone.trimmingCharacters(in: .whitespacesAndNewlines)
            if payoutMethodDraft.type == .bit, !savedPhone.isEmpty, savedPhone != profilePhone {
                pendingProfilePhone = savedPhone
                isOfferingProfilePhoneUpdate = true
            }
        } catch let error as FunctionsError {
            // The backend names the field that failed validation, so surface its
            // message rather than a generic one.
            if case .serverError(let message, let status) = error, status == "INVALID_ARGUMENT" {
                payoutMethodErrorMessage = message
            } else {
                payoutMethodErrorMessage = LocalizationSupport.localized("Could not save your payment method. Please try again.")
            }
            logger.error("[Earnings] failed saving payout method: \(error.localizedDescription)")
        } catch {
            payoutMethodErrorMessage = LocalizationSupport.localized("Could not save your payment method. Please try again.")
            logger.error("[Earnings] failed saving payout method: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "TeacherEarnings.savePayoutMethod")
        }
    }

    /// Confirms the offer to copy a newly saved Bit number onto the profile.
    func confirmProfilePhoneUpdate() async {
        let phone = pendingProfilePhone
        isOfferingProfilePhoneUpdate = false
        pendingProfilePhone = ""
        guard !phone.isEmpty, let uid = Auth.auth().currentUser?.uid else { return }

        do {
            try await UserService.shared.updateProfileFields(uid: uid, fields: ["phoneNumber": phone])
            profilePhone = phone
            logger.info("[Earnings] profile phone updated from payout method")
        } catch {
            // The payout method itself already saved, so this is not worth
            // interrupting the teacher over — the profile just stays as it was.
            logger.error("[Earnings] failed updating profile phone: \(error.localizedDescription)")
        }
    }

    func declineProfilePhoneUpdate() {
        isOfferingProfilePhoneUpdate = false
        pendingProfilePhone = ""
    }

    /// Confirms a PayPal payout account by having the teacher log in to PayPal.
    /// PayPal has no API to check whether an address has an account, so this
    /// login is the only real proof — which is why the PayPal option is saved
    /// here rather than through the Save button.
    ///
    /// Works on both platforms: iOS presents PayPal in an
    /// `ASWebAuthenticationSession`, Android switches out to the browser and
    /// back through an App Link. See PayPalVaultService.
    func connectPayPalPayoutAccount() async {
        guard !isConnectingPayPal else { return }
        isConnectingPayPal = true
        payoutMethodErrorMessage = nil
        defer { isConnectingPayPal = false }

        do {
            let session = try await FunctionsService.shared.createPayPalVaultClientToken()
            let nonce = try await PayPalVaultService.shared.vaultPayPalAccount(clientToken: session.clientToken)
            let confirmed = try await FunctionsService.shared.verifyPayPalPayoutAccount(nonce: nonce)

            var method = TeacherPayoutMethod()
            method.type = .paypal
            method.email = confirmed.email
            method.isPayPalVerified = true

            payoutMethodDraft = method
            payoutMethod = method
            payoutMethodSummary = confirmed.summary
            isEditingPayoutMethod = false
            logger.info("[Earnings] PayPal payout account confirmed")
        } catch let error as PayPalVaultService.PayPalVaultServiceError {
            if case .cancelled = error {
                logger.info("[Earnings] PayPal payout connect cancelled")
            } else {
                payoutMethodErrorMessage = error.localizedDescription
            }
        } catch let error as FunctionsError {
            if case .serverError(let message, _) = error {
                payoutMethodErrorMessage = message
            } else {
                payoutMethodErrorMessage = LocalizationSupport.localized("Could not confirm your PayPal account. Please try again.")
            }
            logger.error("[Earnings] PayPal payout connect failed: \(error.localizedDescription)")
        } catch {
            payoutMethodErrorMessage = LocalizationSupport.localized("Could not confirm your PayPal account. Please try again.")
            logger.error("[Earnings] PayPal payout connect failed: \(error.localizedDescription)")
        }
    }

    /// The backend sends the payout day as "yyyy-MM-dd"; show it the way the
    /// viewer's locale writes dates.
    private static func payoutDateText(_ isoDay: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: isoDay) else { return isoDay }
        return LessonFormatting.dateText(date)
    }
}
