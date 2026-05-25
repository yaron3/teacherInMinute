import Foundation

#if !os(Android)
import FirebaseAuth
import FirebaseDatabase
import FirebaseMessaging
#if os(iOS)
import UIKit
#endif
#else
import SkipFirebaseAuth
import SkipFirebaseMessaging
#endif

@MainActor
public final class PushNotificationService {
    public static let shared = PushNotificationService()

    private var registeredUID: String?
    private var registeredRole: AppUserMode?

    private init() {}

    func registerCurrentDevice(role: AppUserMode) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        registeredUID = uid
        registeredRole = role

        Task {
            _ = await PermissionService.shared.requestNotifications()
#if os(iOS)
            UIApplication.shared.registerForRemoteNotifications()
#endif
            await writeCurrentToken(uid: uid, role: role)
        }
    }

    public func handleAPNSToken(_ token: Data) {
#if !os(Android)
        Messaging.messaging().apnsToken = token
        guard let uid = registeredUID, let role = registeredRole else { return }
        Task {
            await writeCurrentToken(uid: uid, role: role)
        }
#endif
    }

    private func writeCurrentToken(uid: String, role: AppUserMode) async {
        do {
            let token = try await Messaging.messaging().token()
            try await writeToken(token, uid: uid, role: role)
            logger.info("[Push] registered FCM token uid=\(uid) role=\(String(describing: role))")
        } catch {
            logger.error("[Push] FCM token registration failed: \(error.localizedDescription)")
        }
    }

    private func writeToken(_ token: String, uid: String, role: AppUserMode) async throws {
        let updates: [String: Any] = [
            "fcmToken": token,
            "fcmTokenUpdatedAt": Date().timeIntervalSince1970 * 1000.0
        ]

        try await setValues(updates, path: "users/\(uid)")
        if role == .teacher {
            try await setValues(updates, path: "teachers/\(uid)")
        }
    }

    private func setValues(_ values: [String: Any], path: String) async throws {
#if !os(Android)
        let ref = Database.database().reference(withPath: path)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            ref.updateChildValues(values) { error, _ in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
#else
        // TODO: Android FCM token write — wire up via JNI bridge (see AndroidTeacherPresenceWriter pattern)
        logger.info("[Push] Android token write not yet implemented path=\(path)")
#endif
    }
}
