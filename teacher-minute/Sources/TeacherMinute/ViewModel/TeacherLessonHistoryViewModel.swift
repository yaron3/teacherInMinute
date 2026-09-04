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
            // Both the rows and the total come from the earnings summary, so
            // this screen and the Earnings tab are the same set of lessons
            // counted the same way — see TeacherEarningsStore for why they
            // used to differ.
            let summary = try await TeacherEarningsStore.shared.summary()
            let historyLessons = summary.lessons
            totalTimeTaughtText = LessonFormatting.totalDurationText(lessons: historyLessons)
            totalEarningsText = LessonFormatting.currencyText(
                cents: summary.totalEarningsCents,
                currencyCode: summary.currency
            )
            logger.info("[Earnings] teacher total uid=\(uid) lessonCount=\(historyLessons.count) totalCents=\(summary.totalEarningsCents) currency=\(summary.currency)")
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
