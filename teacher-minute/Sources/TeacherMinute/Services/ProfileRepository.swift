import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif



// Base class is the mock: all methods return nil/empty so previews and tests
// never touch Firebase. FirebaseProfileRepository overrides for production.
@MainActor
class ProfileRepository {
    var currentUserId: String? { nil }
    func fetchProfileSummary(uid: String) async throws -> UserProfileSummary? { nil }
    func isTeacherVerified(uid: String) async throws -> Bool { false }
    func fetchUploadedDocuments(uid: String) async throws -> [String] { [] }
    /// A teacher's star average and review count. `nil` when unavailable, so
    /// the profile can leave the rating out rather than show a made-up score.
    func fetchTeacherRating(uid: String) async throws -> TeacherRatingSummary? { nil }
    /// Where the teacher's payout is sent, or `nil` if they have not set one up.
    func fetchPayoutMethod(uid: String) async throws -> TeacherPayoutMethod? { nil }
}

@MainActor
final class FirebaseProfileRepository: ProfileRepository {
    override var currentUserId: String? {
        Auth.auth().currentUser?.uid
    }

    override func fetchProfileSummary(uid: String) async throws -> UserProfileSummary? {
        try await UserService.shared.fetchProfileSummary(uid: uid)
    }

    override func isTeacherVerified(uid: String) async throws -> Bool {
        (try? await UserService.shared.isTeacherVerified(uid: uid)) ?? false
    }

    override func fetchUploadedDocuments(uid: String) async throws -> [String] {
        let data = (try? await UserService.shared.fetchRaw(uid: uid)) ?? [:]
        return data["uploadedDocuments"] as? [String] ?? []
    }

    override func fetchTeacherRating(uid: String) async throws -> TeacherRatingSummary? {
        // `teachers/{uid}` holds the aggregate but is not readable cross-user,
        // so the rating always comes through the backend callable.
        try await FunctionsService.shared.teacherRatingSummary(teacherId: uid)
    }

    override func fetchPayoutMethod(uid: String) async throws -> TeacherPayoutMethod? {
        // Read straight from the teacher's own user document: the earnings
        // service returns the same method, but aggregating every lesson just to
        // show one line on the profile would be a lot of work for a label.
        let data = (try? await UserService.shared.fetchRaw(uid: uid)) ?? [:]
        guard let stored = data["payoutMethod"] as? [String: Any] else { return nil }
        return TeacherPayoutMethod(data: stored)
    }
}
