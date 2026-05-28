import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

@MainActor
enum PermissionsSetupStore {
    private static let keyPrefix = "permissionsSetupCompleted"

    static func hasCompletedForCurrentUser() -> Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return UserDefaults.standard.bool(forKey: key(for: uid))
    }

    static func markCompletedForCurrentUser() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        UserDefaults.standard.set(true, forKey: key(for: uid))
    }

    static func shouldShowForCurrentUser() async -> Bool {
        if hasCompletedForCurrentUser() { return false }

        let permissionService = PermissionService.shared
        let microphoneState = permissionService.captureStatus(for: .microphone)
        let cameraState = permissionService.captureStatus(for: .camera)
        let notificationsState = await permissionService.notificationStatus()
        let hasHandledPermissions = microphoneState != .notDetermined
            || cameraState != .notDetermined
            || notificationsState != .notDetermined

        if hasHandledPermissions {
            markCompletedForCurrentUser()
            return false
        }

        return true
    }

    private static func key(for uid: String) -> String {
        "\(keyPrefix).\(uid)"
    }
}
