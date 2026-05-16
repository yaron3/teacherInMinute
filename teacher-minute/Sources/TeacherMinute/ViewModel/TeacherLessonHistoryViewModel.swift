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

@Observable
@MainActor
final class TeacherLessonHistoryViewModel {
    var teacherName = "Teacher"
    var query = ""
    var selectedLesson: LessonHistoryItem?
    var playingLessonID: LessonHistoryItem.ID?
    var totalTimeTaughtText = "0 min"

    var lessons: [LessonHistoryItem] = []
    
    var filteredLessons: [LessonHistoryItem] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return lessons }
        return lessons.filter { lesson in
            lesson.title.localizedCaseInsensitiveContains(trimmedQuery)
            || lesson.otherParticipant.localizedCaseInsensitiveContains(trimmedQuery)
            || lesson.summary.localizedCaseInsensitiveContains(trimmedQuery)
        }
    }
    
    var completedCountText: String {
        "\(lessons.count) taught"
    }
    
    var totalEarningsText: String {
        let total = lessons.reduce(0.0) { partialResult, lesson in
            partialResult + (Double(lesson.amount.replacingOccurrences(of: "$", with: "")) ?? 0)
        }
        return total.formatted(.currency(code: "USD"))
    }
    
    func view(_ lesson: LessonHistoryItem) {
        selectedLesson = lesson
    }
    
    func toggleAudio(for lesson: LessonHistoryItem) {
        guard lesson.hasAudio else { return }
        playingLessonID = playingLessonID == lesson.id ? nil : lesson.id
    }
    
    func isPlaying(_ lesson: LessonHistoryItem) -> Bool {
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

     static func lessonHistoryItem(_ lesson: HistoryLesson) -> LessonHistoryItem {
        LessonHistoryItem(
            questionId: lesson.questionId,
            title: lesson.title,
            otherParticipant: lesson.otherParticipantName,
            completedAt: LessonFormatting.relativeDateText(lesson.acceptedAt),
            duration: LessonFormatting.shortDurationText(seconds: lesson.durationSeconds),
            amount: LessonFormatting.currencyText(cents: lesson.teacherEarningsCents),
            summary: "Completed lesson with \(lesson.otherParticipantName).",
            transcriptPreview: "Lesson transcript will appear here when available.",
            hasAudio: false
        )
    }
}
