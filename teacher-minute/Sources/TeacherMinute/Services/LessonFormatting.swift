//
//  LessonFormatting.swift
//  teacher-minute
//

import Foundation

enum LessonFormatting {
    static let currencyPreferenceKey = "settings.currency.preference"
    static let defaultCurrencyCode = "USD"

    static var selectedCurrencyCode: String {
        let code = UserDefaults.standard.string(forKey: currencyPreferenceKey) ?? defaultCurrencyCode
        return code.isEmpty ? defaultCurrencyCode : code
    }

    static func relativeDateText(_ date: Date) -> String {
        guard date > .distantPast else { return "Recently" }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today, \(formatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    static func durationText(seconds: Int) -> String {
        let minutes = max(1, Int((Double(max(0, seconds)) / 60.0).rounded(.up)))
        return minutes == 1
            ? LocalizationSupport.localized("1 min")
            : String(format: LocalizationSupport.localized("%lld mins"), Int64(minutes))
    }

    static func shortDurationText(seconds: Int) -> String {
        let minutes = max(1, Int((Double(max(0, seconds)) / 60.0).rounded(.up)))
        return minutes == 1
            ? LocalizationSupport.localized("1 min")
            : String(format: LocalizationSupport.localized("%lld min"), Int64(minutes))
    }

    static func currencyText(cents: Int, currencyCode: String = selectedCurrencyCode) -> String {
        let amount = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = LocalizationSupport.currentLocale
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currencyCode) \(String(format: "%.2f", amount))"
    }

    static func totalDurationText(lessons: [HistoryLesson]) -> String {
        let totalSeconds = lessons.reduce(0) { $0 + $1.durationSeconds }
        let totalMinutes = max(0, Int((Double(totalSeconds) / 60.0).rounded(.up)))
        if totalMinutes == 0 { return String(format: LocalizationSupport.localized("%lld min"), Int64(0)) }
        return totalMinutes == 1
            ? LocalizationSupport.localized("1 min")
            : String(format: LocalizationSupport.localized("%lld min"), Int64(totalMinutes))
    }

    static func totalCostText(lessons: [HistoryLesson]) -> String {
        let totalCents = lessons.reduce(0) { $0 + $1.costCents }
        return currencyText(cents: totalCents)
    }
}
