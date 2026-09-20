//
//  TeacherLaunchPresence.swift
//  teacher-minute
//
//  What the teacher's availability should be when the app starts.
//

import Foundation

/// The teacher's choice of availability at launch.
///
/// Going online is otherwise a deliberate tap on every launch, which a teacher
/// who is always available has to remember, and a teacher who is rarely
/// available never wants done for them. So the choice is theirs to make once.
enum TeacherLaunchPresence: String, CaseIterable, Identifiable {
    /// Come online as soon as the dashboard has the teacher's subjects.
    case online
    /// Stay offline until the teacher taps the toggle. The default.
    case offline
    /// Restore whatever the toggle was left on when the app last closed.
    case lastState

    var id: String { rawValue }

    var title: String {
        switch self {
        case .online: return LocalizationSupport.localized("Online")
        case .offline: return LocalizationSupport.localized("Offline")
        case .lastState: return LocalizationSupport.localized("Last state")
        }
    }
}

/// Keys, defaults and resolution for the teacher's launch availability.
enum TeacherPresencePreferences {
    /// What the app did before this setting existed, and so what an absent
    /// preference means: a fresh launch is offline until the teacher says
    /// otherwise.
    static let defaultLaunchPresence = TeacherLaunchPresence.offline

    /// `@AppStorage` / `UserDefaults` key holding a `TeacherLaunchPresence`
    /// raw value. Absent means `defaultLaunchPresence`.
    static let launchPresenceKey = "teacherLaunchPresence"

    /// Mirrors the availability toggle so `.lastState` has something to
    /// restore. Written on every presence change, including the automatic one
    /// that takes a teacher offline when notifications are refused.
    static let lastKnownOnlineKey = "teacherLastKnownOnline"

    static var launchPresence: TeacherLaunchPresence {
        get {
            let raw = UserDefaults.standard.string(forKey: launchPresenceKey) ?? ""
            return TeacherLaunchPresence(rawValue: raw) ?? defaultLaunchPresence
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: launchPresenceKey)
        }
    }

    static var lastKnownOnline: Bool {
        get { UserDefaults.standard.bool(forKey: lastKnownOnlineKey) }
        set { UserDefaults.standard.set(newValue, forKey: lastKnownOnlineKey) }
    }

    /// Whether the dashboard should put the teacher online once it has their
    /// subjects. Notification permission is still enforced afterwards, so a
    /// teacher who cannot be reached does not silently join the dispatch pool.
    static func shouldGoOnlineAtLaunch() -> Bool {
        switch launchPresence {
        case .online: return true
        case .offline: return false
        case .lastState: return lastKnownOnline
        }
    }
}
