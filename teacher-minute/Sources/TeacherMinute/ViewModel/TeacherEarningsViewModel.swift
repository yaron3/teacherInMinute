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

struct MonthSummary: Identifiable {
    let id: String           // "yyyy-MM"
    let shortName: String    // "יולי"
    let displayName: String  // "יולי 2026 (שוטף)"
    let earningsCents: Int
    let minutesCount: Int
    let lessonCount: Int
    let isCurrentMonth: Bool
    let weeklyBreakdown: [WeekSummary]
}

struct WeekSummary: Identifiable {
    let id: String
    let label: String   // "שבוע 1 (1-7)"
    let earningsCents: Int
    let minutesCount: Int
    let lessonCount: Int
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

    // Next payment — mock until a payment system is implemented
    var nextPaymentCents: Int = 7050
    var nextPaymentDate: String = "03/08/2025"
    var nextPaymentPhone: String = "0521234567"

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
        guard let uid = Auth.auth().currentUser?.uid else {
            applyMock()
            return
        }
        let lessons = (try? await HistoryModel.shared.fetchRecentLessons(for: uid, limit: 100)) ?? []
        if lessons.isEmpty {
            applyMock()
            return
        }

        currencyCode = lessons.first?.currencyCode ?? LessonFormatting.defaultCurrencyCode

        let calendar = Calendar.current
        let now = Date()
        let currentComps = calendar.dateComponents([.year, .month], from: now)
        let currentKey = Self.monthKey(year: currentComps.year ?? 0, month: currentComps.month ?? 0)

        var byMonth: [String: [HistoryLesson]] = [:]
        for lesson in lessons {
            let comps = calendar.dateComponents([.year, .month], from: lesson.acceptedAt)
            let key = Self.monthKey(year: comps.year ?? 0, month: comps.month ?? 0)
            byMonth[key, default: []].append(lesson)
        }

        let sortedKeys = byMonth.keys.sorted()  // ascending — oldest first
        var summaries: [MonthSummary] = []
        for key in sortedKeys {
            let ml = byMonth[key] ?? []
            let comps = calendar.dateComponents([.year, .month], from: ml.first?.acceptedAt ?? now)
            let yr = comps.year ?? 0
            let mo = comps.month ?? 0
            let isCurrent = key == currentKey
            summaries.append(MonthSummary(
                id: key,
                shortName: Self.hebrewMonthName(month: mo),
                displayName: Self.monthDisplayName(year: yr, month: mo, isCurrentMonth: isCurrent),
                earningsCents: ml.reduce(0) { $0 + $1.teacherEarningsCents },
                minutesCount: ml.reduce(0) { $0 + max(1, $1.durationSeconds / 60) },
                lessonCount: ml.count,
                isCurrentMonth: isCurrent,
                weeklyBreakdown: buildWeeklyBreakdown(lessons: ml, year: yr, month: mo)
            ))
        }

        totalEarningsCents = lessons.reduce(0) { $0 + $1.teacherEarningsCents }
        totalMonthsActive = byMonth.keys.count
        months = summaries
        selectedMonthId = summaries.first(where: { $0.isCurrentMonth })?.id ?? summaries.last?.id ?? ""
    }

    private func buildWeeklyBreakdown(lessons: [HistoryLesson], year: Int, month: Int) -> [WeekSummary] {
        let calendar = Calendar.current
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth),
              let lastOfMonth = calendar.date(byAdding: .day, value: -1, to: nextMonth) else { return [] }

        let lastDay = calendar.component(.day, from: lastOfMonth)
        var summaries: [WeekSummary] = []
        var weekNum = 1
        var startDay = 1

        while startDay <= lastDay {
            let endDay = min(startDay + 6, lastDay)
            guard let weekStart = calendar.date(from: DateComponents(year: year, month: month, day: startDay)),
                  let weekEndInclusive = calendar.date(from: DateComponents(year: year, month: month, day: endDay)),
                  let weekEndExclusive = calendar.date(byAdding: .day, value: 1, to: weekEndInclusive) else {
                startDay += 7
                weekNum += 1
                continue
            }
            let weekLessons = lessons.filter { $0.acceptedAt >= weekStart && $0.acceptedAt < weekEndExclusive }
            summaries.append(WeekSummary(
                id: "week-\(weekNum)",
                label: String(format: LocalizationSupport.localized("Week %d (%d-%d)"), weekNum, startDay, endDay),
                earningsCents: weekLessons.reduce(0) { $0 + $1.teacherEarningsCents },
                minutesCount: weekLessons.reduce(0) { $0 + max(1, $1.durationSeconds / 60) },
                lessonCount: weekLessons.count
            ))
            startDay += 7
            weekNum += 1
        }
        return summaries
    }

    private func applyMock() {
        let calendar = Calendar.current
        let now = Date()
        let c = calendar.dateComponents([.year, .month], from: now)
        let yr = c.year ?? 2026
        let mo = c.month ?? 8
        let currentKey = Self.monthKey(year: yr, month: mo)

        let mockWeeks = [
            WeekSummary(id: "week-1", label: String(format: LocalizationSupport.localized("Week %d (%d-%d)"), 1, 1, 7), earningsCents: 1500, minutesCount: 20, lessonCount: 3),
            WeekSummary(id: "week-2", label: String(format: LocalizationSupport.localized("Week %d (%d-%d)"), 2, 8, 14), earningsCents: 2500, minutesCount: 33, lessonCount: 4),
            WeekSummary(id: "week-3", label: String(format: LocalizationSupport.localized("Week %d (%d-%d)"), 3, 15, 21), earningsCents: 1800, minutesCount: 24, lessonCount: 3),
            WeekSummary(id: "week-4", label: String(format: LocalizationSupport.localized("Week %d (%d-%d)"), 4, 22, 31), earningsCents: 1250, minutesCount: 17, lessonCount: 2),
        ]

        var mockMonths: [MonthSummary] = []
        for offset in [2, 1] {
            if let prevDate = calendar.date(byAdding: .month, value: -offset, to: now) {
                let pc = calendar.dateComponents([.year, .month], from: prevDate)
                let py = pc.year ?? yr
                let pm = pc.month ?? mo
                mockMonths.append(MonthSummary(
                    id: Self.monthKey(year: py, month: pm),
                    shortName: Self.hebrewMonthName(month: pm),
                    displayName: Self.monthDisplayName(year: py, month: pm, isCurrentMonth: false),
                    earningsCents: offset == 2 ? 14700 : 20000,
                    minutesCount: offset == 2 ? 196 : 267,
                    lessonCount: offset == 2 ? 26 : 34,
                    isCurrentMonth: false,
                    weeklyBreakdown: []
                ))
            }
        }
        mockMonths.append(MonthSummary(
            id: currentKey,
            shortName: Self.hebrewMonthName(month: mo),
            displayName: Self.monthDisplayName(year: yr, month: mo, isCurrentMonth: true),
            earningsCents: 7050,
            minutesCount: 94,
            lessonCount: 12,
            isCurrentMonth: true,
            weeklyBreakdown: mockWeeks
        ))

        months = mockMonths
        totalEarningsCents = mockMonths.reduce(0) { $0 + $1.earningsCents }
        totalMonthsActive = mockMonths.count
        selectedMonthId = currentKey
        nextPaymentCents = 7050
    }

    private static func monthKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month)
    }

    static func hebrewMonthName(month: Int) -> String {
        let names = ["ינואר", "פברואר", "מרץ", "אפריל", "מאי", "יוני",
                     "יולי", "אוגוסט", "ספטמבר", "אוקטובר", "נובמבר", "דצמבר"]
        guard month >= 1, month <= 12 else { return "\(month)" }
        return names[month - 1]
    }

    private static func monthDisplayName(year: Int, month: Int, isCurrentMonth: Bool) -> String {
        let name = hebrewMonthName(month: month)
        return isCurrentMonth ? "\(name) \(year) (שוטף)" : "\(name) \(year)"
    }
}
