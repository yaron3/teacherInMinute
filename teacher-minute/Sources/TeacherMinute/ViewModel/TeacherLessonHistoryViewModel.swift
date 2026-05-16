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
    let questionId: String
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
    var totalTimeTaughtText = "0 min"

    var lessons: [TeacherLessonHistoryItem] = []
    
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
            totalTimeTaughtText = LessonFormatting.totalDurationText(lessons: historyLessons)
            if !historyLessons.isEmpty {
                lessons = historyLessons.map(Self.lessonHistoryItem)
            }
        } catch {
            logger.error("[TeacherLessons] failed loading profile: \(error.localizedDescription)")
        }
    }

    private static func lessonHistoryItem(_ lesson: HistoryLesson) -> TeacherLessonHistoryItem {
        TeacherLessonHistoryItem(
            questionId: lesson.questionId,
            title: lesson.title,
            student: lesson.otherParticipantName,
            completedAt: LessonFormatting.relativeDateText(lesson.acceptedAt),
            duration: LessonFormatting.shortDurationText(seconds: lesson.durationSeconds),
            earnings: LessonFormatting.currencyText(cents: lesson.teacherEarningsCents),
            summary: "Completed lesson with \(lesson.otherParticipantName).",
            transcriptPreview: "Lesson transcript will appear here when available.",
            hasAudio: false
        )
    }
}
