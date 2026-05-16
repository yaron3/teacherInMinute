//
//  LessonFormatting.swift
//  teacher-minute
//

import Foundation

enum LessonFormatting {

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
        return minutes == 1 ? "1 min" : "\(minutes) mins"
    }

    static func shortDurationText(seconds: Int) -> String {
        let minutes = max(1, Int((Double(max(0, seconds)) / 60.0).rounded(.up)))
        return minutes == 1 ? "1 min" : "\(minutes) min"
    }

    static func currencyText(cents: Int) -> String {
        (Double(cents) / 100.0).formatted(.currency(code: "USD"))
    }

    static func totalDurationText(lessons: [HistoryLesson]) -> String {
        let totalSeconds = lessons.reduce(0) { $0 + $1.durationSeconds }
        let totalMinutes = max(0, Int((Double(totalSeconds) / 60.0).rounded(.up)))
        if totalMinutes == 0 { return "0 min" }
        return totalMinutes == 1 ? "1 min" : "\(totalMinutes) min"
    }

    static func totalCostText(lessons: [HistoryLesson]) -> String {
        let totalCents = lessons.reduce(0) { $0 + $1.costCents }
        return currencyText(cents: totalCents)
    }
}
