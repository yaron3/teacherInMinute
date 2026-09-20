//
//  StudentLessonHistoryViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy specific to the student's side of lesson history; everything the
//  screen shares with the teacher's side lives in `LessonHistoryViewModeling`.
//

import Foundation

extension StudentLessonHistoryViewModel {
    var historyEyebrow: String { LocalizationSupport.localized("Lesson History") }
    var searchPlaceholder: String { LocalizationSupport.localized("Search lessons or teachers") }
    var timeLearnedTitle: String { LocalizationSupport.localized("Time Learned") }

    /// Students see what a lesson cost them, teachers what they earned.
    var costLabel: String { LocalizationSupport.localized("Cost") }
}
