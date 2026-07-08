//
//  TeacherDocumentsPromptStore.swift
//  teacher-minute
//
//  During onboarding only the front of the government ID is mandatory (bug #24).
//  After a teacher completes their first real lesson (longer than one minute) we
//  gently suggest — but never force — completing the remaining optional
//  documents. This store records the per-user state that gates that one-time
//  suggestion; the teacher can always finish the documents later from Profile.
//

import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

@MainActor
enum TeacherDocumentsPromptStore {
    /// A lesson must last at least this long to count as a "real" first lesson.
    static let minimumLessonSeconds = 60

    private static let lessonKeyPrefix = "teacherDocs.firstLessonCompleted"
    private static let suggestedKeyPrefix = "teacherDocs.suggestionShown"

    /// Records that the teacher has completed a lesson longer than a minute,
    /// making them eligible for the "finish your documents" suggestion.
    static func markLessonCompleted() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(true, forKey: key(lessonKeyPrefix, uid))
    }

    static func hasCompletedLesson() -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return UserDefaults.standard.bool(forKey: key(lessonKeyPrefix, uid))
    }

    /// Records that we've shown the suggestion (whether or not they acted on it),
    /// so we don't nag on every subsequent visit.
    static func markSuggestionShown() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(true, forKey: key(suggestedKeyPrefix, uid))
    }

    static func hasShownSuggestion() -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return UserDefaults.standard.bool(forKey: key(suggestedKeyPrefix, uid))
    }

    /// Whether to present the suggestion now: the teacher finished a qualifying
    /// lesson, we haven't suggested yet, and they still have documents to upload.
    static func shouldPresentSuggestion() async -> Bool {
        guard hasCompletedLesson(), !hasShownSuggestion() else { return false }
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        let data = (try? await UserService.shared.fetchRaw(uid: uid)) ?? [:]
        let docs = (data["uploadedDocuments"] as? [String]) ?? []
        return hasMissingDocuments(docs)
    }

    /// True when any of the four verification documents is still missing.
    static func hasMissingDocuments(_ docs: [String]) -> Bool {
        let hasFront = docs.contains { $0.contains("_front") }
        let hasBack = docs.contains { $0.contains("_back") }
        let hasCredentials = docs.contains { $0.hasPrefix("credentials_") }
        let hasSelfie = docs.contains { $0.hasPrefix("selfie_") }
        return !(hasFront && hasBack && hasCredentials && hasSelfie)
    }

    private static func key(_ prefix: String, _ uid: String) -> String {
        "\(prefix).\(uid)"
    }
}
