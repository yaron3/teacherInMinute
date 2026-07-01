//
//  NotificationPromptStore.swift
//  teacher-minute
//
//  Tracks when to ask a student for notification permission. We deliberately
//  avoid the system prompt during onboarding; instead we wait until after the
//  student's first lesson and show a custom explanation first. This store
//  records the per-user state that gates that flow.
//

import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

@MainActor
enum NotificationPromptStore {
    private static let lessonKeyPrefix = "notif.firstLessonCompleted"
    private static let promptedKeyPrefix = "notif.explanationShown"

    /// Records that the student has completed a lesson, making them eligible for
    /// the notification permission explanation on their next return home.
    static func markLessonCompleted() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(true, forKey: key(lessonKeyPrefix, uid))
    }

    static func hasCompletedLesson() -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return UserDefaults.standard.bool(forKey: key(lessonKeyPrefix, uid))
    }

    /// Records that we've shown the explanation (whether or not the user opted
    /// in), so we don't nag on every subsequent visit.
    static func markExplanationShown() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(true, forKey: key(promptedKeyPrefix, uid))
    }

    static func hasShownExplanation() -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return UserDefaults.standard.bool(forKey: key(promptedKeyPrefix, uid))
    }

    /// Whether to present the explanation now: the student finished a lesson, we
    /// haven't asked yet, and the OS permission is still undetermined (so the
    /// system dialog can still appear if they opt in).
    static func shouldPresentExplanation() async -> Bool {
        guard hasCompletedLesson(), !hasShownExplanation() else { return false }
        return await PermissionService.shared.notificationStatus() == .notDetermined
    }

    private static func key(_ prefix: String, _ uid: String) -> String {
        "\(prefix).\(uid)"
    }
}
