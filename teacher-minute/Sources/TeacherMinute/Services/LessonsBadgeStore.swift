//
//  LessonsBadgeStore.swift
//  teacher-minute
//
//  Tracks how many lessons the user had already seen the last time they opened
//  the Lessons tab. The tab badge is shown only when new lessons were added
//  since then and the user hasn't opened the tab yet — never for lessons that
//  already existed before we started tracking.
//

import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

enum LessonsBadgeStore {
    private static let seenCountKeyPrefix = "lessons.seenCount"

    /// The lesson count recorded the last time the user opened the Lessons tab,
    /// or `nil` if we've never recorded it for this user yet.
    static func seenCount() -> Int? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let key = key(seenCountKeyPrefix, uid)
        guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
        return UserDefaults.standard.integer(forKey: key)
    }

    /// Records that the user has now seen `count` lessons — clears the badge.
    static func markSeen(count: Int) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(count, forKey: key(seenCountKeyPrefix, uid))
    }

    private static func key(_ prefix: String, _ uid: String) -> String {
        "\(prefix).\(uid)"
    }
}
