//
//  TeacherLessonHistoryViewModel.swift
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

struct TeacherLessonHistoryItem: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let student: String
    let completedAt: String
    let duration: String
    let earnings: String
    let summary: String
    let transcriptPreview: String
    let hasAudio: Bool
}

@Observable
@MainActor
final class TeacherLessonHistoryViewModel {
    var teacherName = "Teacher"
    var query = ""
    var selectedLesson: TeacherLessonHistoryItem?
    var playingLessonID: TeacherLessonHistoryItem.ID?
    
    var lessons = [
        TeacherLessonHistoryItem(
            title: "Calculus Help",
            student: "Sarah Jenkins",
            completedAt: "Today, 2:30 PM",
            duration: "14 min",
            earnings: "$14.20",
            summary: "Guided Sarah through derivative rules and chain-rule problem setup.",
            transcriptPreview: "First identify the outside function, then multiply by the derivative of the inside expression.",
            hasAudio: true
        ),
        TeacherLessonHistoryItem(
            title: "Limits Review",
            student: "Noah Kim",
            completedAt: "Yesterday",
            duration: "19 min",
            earnings: "$19.40",
            summary: "Reviewed one-sided limits, graph interpretation, and removable discontinuities.",
            transcriptPreview: "The left-hand and right-hand limits need to meet before the full limit exists.",
            hasAudio: true
        ),
        TeacherLessonHistoryItem(
            title: "Geometry Proofs",
            student: "Ava Brown",
            completedAt: "May 7",
            duration: "24 min",
            earnings: "$24.50",
            summary: "Built a two-column proof using congruent triangles and parallel-line angle rules.",
            transcriptPreview: "Start by writing the given statements, then use alternate interior angles for the parallel lines.",
            hasAudio: false
        )
    ]
    
    var filteredLessons: [TeacherLessonHistoryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return lessons }
        return lessons.filter { lesson in
            lesson.title.localizedCaseInsensitiveContains(trimmedQuery)
            || lesson.student.localizedCaseInsensitiveContains(trimmedQuery)
            || lesson.summary.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
    
    var completedCountText: String {
        "\(lessons.count) taught"
    }
    
    var totalEarningsText: String {
        let total = lessons.reduce(0.0) { partialResult, lesson in
            partialResult + (Double(lesson.earnings.replacingOccurrences(of: "$", with: "")) ?? 0)
        }
        return total.formatted(.currency(code: "USD"))
    }
    
    func view(_ lesson: TeacherLessonHistoryItem) {
        selectedLesson = lesson
    }
    
    func toggleAudio(for lesson: TeacherLessonHistoryItem) {
        guard lesson.hasAudio else { return }
        playingLessonID = playingLessonID == lesson.id ? nil : lesson.id
    }
    
    func isPlaying(_ lesson: TeacherLessonHistoryItem) -> Bool {
        playingLessonID == lesson.id
    }
    
    func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            if let profile = try await UserService.shared.fetchProfileSummary(uid: uid) {
                teacherName = profile.displayName
            }
            let historyLessons = try await HistoryModel.shared.fetchRecentLessons(for: uid, limit: 100)
            if !historyLessons.isEmpty {
                lessons = historyLessons.map(Self.lessonHistoryItem)
            }
        } catch {
            logger.error("[TeacherLessons] failed loading profile: \(error.localizedDescription)")
        }
    }

    private static func lessonHistoryItem(_ lesson: HistoryLesson) -> TeacherLessonHistoryItem {
        TeacherLessonHistoryItem(
            title: lesson.title,
            student: lesson.otherParticipantName,
            completedAt: dateText(lesson.acceptedAt),
            duration: durationText(seconds: lesson.durationSeconds),
            earnings: currencyText(cents: lesson.teacherEarningsCents),
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
