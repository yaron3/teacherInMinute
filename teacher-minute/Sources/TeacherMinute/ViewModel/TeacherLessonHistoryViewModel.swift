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
    var totalTimeTaughtText = LessonFormatting.totalDurationText(lessons: [])
    var totalEarningsText = LessonFormatting.currencyText(cents: 0)
    var profileImageURL = ""
    var isInitialLoading = true

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
        String(format: LocalizationSupport.localized("%d taught"), lessons.count)
    }
    
    func view(_ lesson: LessonHistoryItem) {
        selectedLessonDetails = nil
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
        defer { isInitialLoading = false }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            if let profile = try await UserService.shared.fetchProfileSummary(uid: uid) {
                teacherName = profile.displayName
                profileImageURL = profile.profileImageURL
            }
            let historyLessons = try await HistoryModel.shared.fetchRecentLessons(for: uid, limit: 100)
            totalTimeTaughtText = LessonFormatting.totalDurationText(lessons: historyLessons)
            var earningsByCurrency: [String: Int] = [:]
            for lesson in historyLessons {
                earningsByCurrency[lesson.currencyCode, default: 0] += lesson.teacherEarningsCents
            }
            logger.info("[Earnings] teacher total uid=\(uid) lessonCount=\(historyLessons.count) totalByCurrency=\(earningsByCurrency)")
            let earningsFormatted = earningsByCurrency
                .sorted { $0.key < $1.key }
                .map { LessonFormatting.currencyText(cents: $0.value, currencyCode: $0.key) }
                .joined(separator: " + ")
            totalEarningsText = earningsFormatted.isEmpty
                ? LessonFormatting.currencyText(cents: 0)
                : earningsFormatted
            lessons = historyLessons.map { Self.lessonHistoryItem($0, currentUserImageURL: profileImageURL) }
        } catch {
            logger.error("[TeacherLessons] failed loading profile: \(error.localizedDescription)")
            AnalyticsService.shared.recordPermissionIfNeeded(error, context: "TeacherLessons.loadProfile")
        }
    }

    func isLoading(_ lesson: LessonHistoryItem) -> Bool { false }

    static func lessonHistoryItem(_ lesson: HistoryLesson, currentUserImageURL: String) -> LessonHistoryItem {
        LessonHistoryItem(
            questionId: lesson.questionId,
            title: lesson.title,
            otherParticipant: lesson.otherParticipantName,
            otherParticipantImageURL: lesson.otherParticipantImageURL,
            currentUserImageURL: currentUserImageURL,
            completedAt: LessonFormatting.relativeDateText(lesson.acceptedAt),
            duration: LessonFormatting.shortDurationText(seconds: lesson.durationSeconds),
            amount: LessonFormatting.currencyText(cents: lesson.teacherEarningsCents, currencyCode: lesson.currencyCode),
            amountCents: lesson.teacherEarningsCents,
            summary: String(
                format: LocalizationSupport.localized("Completed lesson with %@."),
                lesson.otherParticipantName
            ),
            transcriptPreview: LocalizationSupport.localized("Lesson transcript will appear here when available."),
            hasAudio: false,
            questionPhotoUrls: lesson.questionPhotoUrls
        )
    }
}
