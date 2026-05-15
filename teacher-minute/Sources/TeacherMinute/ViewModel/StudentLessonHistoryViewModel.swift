//
//  StudentLessonHistoryViewModel.swift
//  teacher-minute
//
//  Created by Codex on 10/05/2026.
//

import Foundation
import Observation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

struct StudentLessonHistoryItem: Identifiable, Hashable {
    let id = UUID()
    let questionId: String
    let title: String
    let teacher: String
    let completedAt: String
    let duration: String
    let price: String
    let summary: String
    let transcriptPreview: String
    let hasAudio: Bool
}

@Observable
@MainActor
final class StudentLessonHistoryViewModel {
    var studentName = "Student"
    var query = ""
    var selectedLesson: StudentLessonHistoryItem?
    var playingLessonID: StudentLessonHistoryItem.ID?
    
    var lessons = [
        StudentLessonHistoryItem(
            questionId: "mock-1",
            title: "Calculus Help",
            teacher: "Mr. Davis",
            completedAt: "Today, 2:30 PM",
            duration: "14 min",
            price: "$16.80",
            summary: "Reviewed derivative rules and solved three chain-rule problems.",
            transcriptPreview: "We started by identifying the outer function, then multiplied by the derivative of the inside expression.",
            hasAudio: true
        ),
        StudentLessonHistoryItem(
            questionId: "mock-2",
            title: "Algebra II",
            teacher: "Ms. Chen",
            completedAt: "Yesterday",
            duration: "22 min",
            price: "$11.00",
            summary: "Factored quadratic expressions and checked answers by expanding.",
            transcriptPreview: "When the leading coefficient is one, look for two numbers that multiply to c and add to b.",
            hasAudio: true
        ),
        StudentLessonHistoryItem(
            questionId: "mock-3",
            title: "Geometry Proofs",
            teacher: "Dr. Patel",
            completedAt: "May 7",
            duration: "18 min",
            price: "$21.60",
            summary: "Built a two-column proof using congruent triangles and parallel-line angle rules.",
            transcriptPreview: "Mark the given angles first, then use alternate interior angles to connect the parallel lines.",
            hasAudio: false
        )
    ]
    
    var filteredLessons: [StudentLessonHistoryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return lessons }
        return lessons.filter { lesson in
            lesson.title.localizedCaseInsensitiveContains(trimmedQuery)
            || lesson.teacher.localizedCaseInsensitiveContains(trimmedQuery)
            || lesson.summary.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
    
    var completedCountText: String {
        "\(lessons.count) completed"
    }
    
    var totalSpendText: String {
        let total = lessons.reduce(0.0) { partialResult, lesson in
            partialResult + (Double(lesson.price.replacingOccurrences(of: "$", with: "")) ?? 0)
        }
        return total.formatted(.currency(code: "USD"))
    }
    
    func view(_ lesson: StudentLessonHistoryItem) {
        selectedLesson = lesson
    }
    
    func toggleAudio(for lesson: StudentLessonHistoryItem) {
        guard lesson.hasAudio else { return }
        playingLessonID = playingLessonID == lesson.id ? nil : lesson.id
    }
    
    func isPlaying(_ lesson: StudentLessonHistoryItem) -> Bool {
        playingLessonID == lesson.id
    }
    
    func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            if let profile = try await UserService.shared.fetchProfileSummary(uid: uid) {
                studentName = profile.displayName
            }
            let historyLessons = try await HistoryModel.shared.fetchRecentLessons(for: uid, limit: 100)
            if !historyLessons.isEmpty {
                lessons = historyLessons.map(Self.lessonHistoryItem)
            }
        } catch {
            logger.error("[StudentLessons] failed loading profile: \(error.localizedDescription)")
        }
    }

    private static func lessonHistoryItem(_ lesson: HistoryLesson) -> StudentLessonHistoryItem {
        StudentLessonHistoryItem(
		  questionId: lesson.questionId,
            title: lesson.title,
            teacher: lesson.otherParticipantName,
            completedAt: dateText(lesson.acceptedAt),
            duration: durationText(seconds: lesson.durationSeconds),
            price: currencyText(cents: lesson.costCents),
            summary: "Completed lesson with \(lesson.otherParticipantName).",
            transcriptPreview: "Lesson transcript will appear here when available.",
            hasAudio: false
        )
    }

    private static func dateText(_ date: Date) -> String {
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

    private static func durationText(seconds: Int) -> String {
        let minutes = max(1, Int((Double(max(0, seconds)) / 60.0).rounded(.up)))
        return minutes == 1 ? "1 min" : "\(minutes) min"
    }

    private static func currencyText(cents: Int) -> String {
        (Double(cents) / 100.0).formatted(.currency(code: "USD"))
    }
}
