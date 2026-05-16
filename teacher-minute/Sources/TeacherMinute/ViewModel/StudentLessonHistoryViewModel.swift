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
    var totalTimeLearnedText = "0 min"

    var lessons: [StudentLessonHistoryItem] = []
    
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
            totalTimeLearnedText = LessonFormatting.totalDurationText(lessons: historyLessons)
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
            completedAt: LessonFormatting.relativeDateText(lesson.acceptedAt),
            duration: LessonFormatting.shortDurationText(seconds: lesson.durationSeconds),
            price: LessonFormatting.currencyText(cents: lesson.costCents),
            summary: "Completed lesson with \(lesson.otherParticipantName).",
            transcriptPreview: "Lesson transcript will appear here when available.",
            hasAudio: false
        )
    }
}
