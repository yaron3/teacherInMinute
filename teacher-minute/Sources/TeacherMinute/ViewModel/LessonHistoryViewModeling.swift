//
//  LessonHistoryViewModeling.swift
//  teacher-minute
//
//  The student's and the teacher's lesson history are the same screen seen
//  from two sides, and they share their row, detail and bubble components.
//  This protocol is what those shared components read their copy from, so a
//  label cannot drift between the two histories.
//

import Foundation

protocol LessonHistoryViewModeling: AnyObject {}

extension LessonHistoryViewModeling {

    // MARK: List
    var pastLessonsTitle: String { LocalizationSupport.localized("Past Lessons") }
    var pastSectionTitle: String { LocalizationSupport.localized("Past") }
    var emptyHistoryText: String {
        LocalizationSupport.localized("You don't have any recent activity")
    }
    var loadingSessionDetailsLabel: String {
        LocalizationSupport.localized("Loading session details")
    }

    // MARK: Detail
    var lessonDetailTitle: String { LocalizationSupport.localized("Lesson") }
    var durationTitle: String { LocalizationSupport.localized("Duration") }
    var originalQuestionTitle: String { LocalizationSupport.localized("Original Question") }
    var summaryTitle: String { LocalizationSupport.localized("Summary") }
    var chatMessagesTitle: String { LocalizationSupport.localized("Chat Messages") }
    var transcriptPreviewTitle: String { LocalizationSupport.localized("Transcript Preview") }

    var listenToLessonLabel: String { LocalizationSupport.localized("Listen to Lesson") }
    var pauseAudioLabel: String { LocalizationSupport.localized("Pause Audio") }

    func audioActionLabel(isPlaying: Bool) -> String {
        isPlaying ? pauseAudioLabel : listenToLessonLabel
    }

    // MARK: Chat bubbles
    var audioMessageLabel: String { LocalizationSupport.localized("Audio message") }
    var videoMessageLabel: String { LocalizationSupport.localized("Video message") }
}

extension StudentLessonHistoryViewModel: LessonHistoryViewModeling {}
extension TeacherLessonHistoryViewModel: LessonHistoryViewModeling {}
