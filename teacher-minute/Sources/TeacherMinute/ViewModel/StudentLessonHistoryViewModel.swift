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

struct LessonHistoryItem: Identifiable, Hashable {
    let id = UUID()
    let questionId: String
    let title: String
    let otherParticipant: String
    let otherParticipantImageURL: String
    let currentUserImageURL: String
    let completedAt: String
    let duration: String
    let amount: String
    let amountCents: Int
    let summary: String
    let transcriptPreview: String
    let hasAudio: Bool
}

struct LessonDetails {
    let questionText: String
    let messages: [LessonMessage]
}

@Observable
@MainActor
final class StudentLessonHistoryViewModel {
    var studentName = "Student"
    var query = ""
    var selectedLesson: LessonHistoryItem?
    var selectedLessonDetails: LessonDetails?
    var playingLessonID: LessonHistoryItem.ID?
    var totalTimeLearnedText = LessonFormatting.totalDurationText(lessons: [])
    var totalSpendText = LessonFormatting.currencyText(cents: 0)
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
        String(format: LocalizationSupport.localized("%lld completed"), Int64(lessons.count))
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
                studentName = profile.displayName
                profileImageURL = profile.profileImageURL
            }
            let historyLessons = try await HistoryModel.shared.fetchRecentLessons(for: uid, limit: 100)
            totalTimeLearnedText = LessonFormatting.totalDurationText(lessons: historyLessons)
            totalSpendText = LessonFormatting.totalCostText(lessons: historyLessons)
            lessons = historyLessons.map { Self.lessonHistoryItem($0, currentUserImageURL: profileImageURL) }
        } catch {
            logger.error("[StudentLessons] failed loading profile: \(error.localizedDescription)")
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
            logger.error("[StudentLessons] failed loading lesson details: \(error.localizedDescription)")
            return LessonDetails(questionText: "", messages: [])
        }
    }

    private static func lessonHistoryItem(_ lesson: HistoryLesson, currentUserImageURL: String) -> LessonHistoryItem {
        LessonHistoryItem(
            questionId: lesson.questionId,
            title: lesson.title,
            otherParticipant: lesson.otherParticipantName,
            otherParticipantImageURL: lesson.otherParticipantImageURL,
            currentUserImageURL: currentUserImageURL,
            completedAt: LessonFormatting.relativeDateText(lesson.acceptedAt),
            duration: LessonFormatting.shortDurationText(seconds: lesson.durationSeconds),
            amount: LessonFormatting.currencyText(cents: lesson.costCents),
            amountCents: lesson.costCents,
            summary: String(
                format: LocalizationSupport.localized("Completed lesson with %@."),
                lesson.otherParticipantName
            ),
            transcriptPreview: LocalizationSupport.localized("Lesson transcript will appear here when available."),
            hasAudio: false
        )
    }
}
