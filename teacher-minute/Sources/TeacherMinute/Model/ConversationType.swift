//
//  ConversationType.swift
//  teacher-minute
//
//  Wire format for the student's chosen session medium. Raw strings are kept
//  identical to the values produced by the backend so the same vocabulary
//  flows through Firestore / RTDB invites without translation.
//

import Foundation

enum ConversationType: String, CaseIterable {
    case text
    case audio
    case video

    var requiresMic: Bool { self == .audio || self == .video }
    var requiresCamera: Bool { self == .video }

    /// Localized label shown to students when picking a session medium.
    var displayName: String {
        switch self {
        case .text: return LocalizationSupport.localized("Text")
        case .audio: return LocalizationSupport.localized("Audio")
        case .video: return LocalizationSupport.localized("Video")
        }
    }
}

/// Keys and defaults for student session preferences that are configurable in
/// Settings and read where a session is initiated.
enum SessionPreferences {
    /// `@AppStorage` / `UserDefaults` key for the student's preferred default
    /// session type. Absent value means "audio call".
    static let defaultQuestionTypeKey = "defaultQuestionType"
}
