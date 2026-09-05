import Foundation
import Observation

/// Single source of truth for the current logged-in user's profile image URL.
///
/// Both home-tab view models (TeacherDashboardViewModel and StudentHomeViewModel)
/// cache the profile URL after the first Firestore load and never re-read it.
/// ProfileViewModel writes here whenever the user uploads a new photo, so the
/// home tabs pick up the change without a full profile re-load.
@Observable
@MainActor
final class UserPhotoStore {
    static let shared = UserPhotoStore()

    var profileImageURL = ""

    private init() {}
}
