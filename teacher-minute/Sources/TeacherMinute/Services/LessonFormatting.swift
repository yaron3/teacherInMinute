//
//  LessonFormatting.swift
//  teacher-minute
//

import Foundation

enum LessonFormatting {
    static let defaultCurrencyCode = "ILS"

    static func relativeDateText(_ date: Date) -> String {
        guard date > .distantPast else { return "Recently" }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return "Today, \(formatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return LocalizationSupport.localized("Yesterday")
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

    static func currencyText(cents: Int, currencyCode: String = defaultCurrencyCode) -> String {
        let amount = Double(cents) / 100.0
        let isWholeAmount = cents % 100 == 0
        if shouldPlaceCurrencySymbolAfterAmount(currencyCode: currencyCode) {
            return "\(numberText(amount: amount, maximumFractionDigits: isWholeAmount ? 0 : 2))\(currencySymbol(for: currencyCode))"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = LocalizationSupport.currentLocale
        formatter.maximumFractionDigits = isWholeAmount ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? "\(currencyCode) \(String(format: "%.2f", amount))"
    }

    private static func numberText(amount: Double, maximumFractionDigits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = LocalizationSupport.currentLocale
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.\(maximumFractionDigits)f", amount)
    }

    private static func shouldPlaceCurrencySymbolAfterAmount(currencyCode: String) -> Bool {
        currencyCode.uppercased() == "ILS" || LocalizationSupport.layoutDirection == .rightToLeft
    }

    private static func currencySymbol(for currencyCode: String) -> String {
        if currencyCode.uppercased() == "ILS" {
            return "₪"
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.locale = LocalizationSupport.currentLocale
        return formatter.currencySymbol ?? currencyCode
    }

    static func totalDurationText(lessons: [HistoryLesson]) -> String {
        let totalSeconds = lessons.reduce(0) { $0 + $1.durationSeconds }
        let totalMinutes = max(0, Int((Double(totalSeconds) / 60.0).rounded(.up)))
        return minutesText(totalMinutes)
    }

    static func minutesText(_ minutes: Int) -> String {
        let displayMinutes = max(0, minutes)
        if displayMinutes == 0 { return String(format: LocalizationSupport.localized("%lld min"), Int64(0)) }
        return displayMinutes == 1
            ? LocalizationSupport.localized("1 min")
            : String(format: LocalizationSupport.localized("%lld min"), Int64(displayMinutes))
    }

    static func totalCostText(lessons: [HistoryLesson], currencyCode: String? = nil) -> String {
        let totalCents = lessons.reduce(0) { $0 + $1.costCents }
        let displayCurrencyCode = currencyCode ?? lessons.first?.currencyCode ?? defaultCurrencyCode
        return currencyText(cents: totalCents, currencyCode: displayCurrencyCode)
    }
}
