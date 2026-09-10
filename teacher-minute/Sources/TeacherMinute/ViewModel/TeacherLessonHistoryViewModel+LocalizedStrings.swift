//
//  TeacherLessonHistoryViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy specific to the teacher's side of lesson history; everything the
//  screen shares with the student's side lives in `LessonHistoryViewModeling`.
//

import Foundation

extension TeacherLessonHistoryViewModel {
    var historyEyebrow: String { LocalizationSupport.localized("Teacher") }
    var searchPlaceholder: String { LocalizationSupport.localized("Search lessons or students") }
    var timeTaughtTitle: String { LocalizationSupport.localized("Time Taught") }
    var earningsLabel: String { LocalizationSupport.localized("Earnings") }
}
