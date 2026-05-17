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
    var selectedLessonDetails: LessonDetails?
    var playingLessonID: LessonHistoryItem.ID?
    var totalTimeTaughtText = "0 min"
    var totalEarningsText = "$0.00"
    var loadingLessonID: LessonHistoryItem.ID?
    var profileImageURL = ""

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
    
    func view(_ lesson: LessonHistoryItem) async {
        guard loadingLessonID == nil else { return }
        loadingLessonID = lesson.id
        selectedLessonDetails = await loadDetails(for: lesson)
        selectedLesson = lesson
        loadingLessonID = nil
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
                profileImageURL = profile.profileImageURL
            }
            let historyLessons = try await HistoryModel.shared.fetchRecentLessons(for: uid, limit: 100)
            totalTimeTaughtText = LessonFormatting.totalDurationText(lessons: historyLessons)
            totalEarningsText = LessonFormatting.currencyText(
                cents: historyLessons.reduce(0) { $0 + $1.teacherEarningsCents }
            )
            lessons = historyLessons.map { Self.lessonHistoryItem($0, currentUserImageURL: profileImageURL) }
        } catch {
            logger.error("[TeacherLessons] failed loading profile: \(error.localizedDescription)")
        }
    }

    func isLoading(_ lesson: LessonHistoryItem) -> Bool {
        loadingLessonID == lesson.id
    }

    private func loadDetails(for lesson: LessonHistoryItem) async -> LessonDetails {
        do {
            let questionText = try await HistoryModel.shared.fetchQuestionText(questionId: lesson.questionId)
            let messages = try await HistoryModel.shared.fetchLessonMessages(questionId: lesson.questionId)
            return LessonDetails(questionText: questionText, messages: messages)
        } catch {
            logger.error("[TeacherLessons] failed loading lesson details: \(error.localizedDescription)")
            return LessonDetails(questionText: "", messages: [])
        }
    }

    static func lessonHistoryItem(_ lesson: HistoryLesson, currentUserImageURL: String) -> LessonHistoryItem {
        LessonHistoryItem(
            questionId: lesson.questionId,
            title: lesson.title,
            otherParticipant: lesson.otherParticipantName,
            otherParticipantImageURL: lesson.otherParticipantImageURL,
            currentUserImageURL: currentUserImageURL,
            completedAt: LessonFormatting.relativeDateText(lesson.acceptedAt),
            duration: LessonFormatting.shortDurationText(seconds: lesson.durationSeconds),
            amount: LessonFormatting.currencyText(cents: lesson.teacherEarningsCents),
            amountCents: lesson.teacherEarningsCents,
            summary: "Completed lesson with \(lesson.otherParticipantName).",
            transcriptPreview: "Lesson transcript will appear here when available.",
            hasAudio: false
        )
    }
}
