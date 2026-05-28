import Foundation

#if !os(Android)
import FirebaseAuth
import FirebaseDatabase
import FirebaseMessaging
import UserNotifications
#if os(iOS)
import UIKit
#endif
#else
import SkipFirebaseAuth
import SkipFirebaseMessaging
#endif

@MainActor
public final class PushNotificationService: NSObject {
    public static let shared = PushNotificationService()

    private var registeredUID: String?
    private var registeredRole: AppUserMode?

    private override init() {
        super.init()
    }

#if !os(Android)
    public func configureDelegates() {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
    }
#else
    public func configureDelegates() {}
#endif

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
#if !os(Android)
        let updates: [String: Any] = [
            "fcmToken": token,
            "fcmTokenUpdatedAt": Date().timeIntervalSince1970 * 1000.0
        ]

        try await setValues(updates, path: "users/\(uid)")
        if role == .teacher {
            try await setValues(updates, path: "teachers/\(uid)")
        }
#else
        AndroidPushTokenWriter.writeToken(token, uid: uid, isTeacher: role == .teacher)
#endif
    }

#if !os(Android)
    private func setValues(_ values: [String: Any], path: String) async throws {
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
    }
#endif
}

#if !os(Android)
extension PushNotificationService: UNUserNotificationCenterDelegate {
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String ?? "unknown"
        Task { @MainActor in
            logger.info("[Push] tapped notification type=\(type)")
            AnalyticsService.shared.logEvent(AnalyticsEvent.notificationOpened, parameters: ["type": type])
        }
        completionHandler()
    }
}

extension PushNotificationService: MessagingDelegate {
    nonisolated public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            guard let uid = self.registeredUID, let role = self.registeredRole else { return }
            do {
                try await self.writeToken(fcmToken, uid: uid, role: role)
                logger.info("[Push] refreshed FCM token uid=\(uid)")
            } catch {
                logger.error("[Push] FCM token refresh write failed: \(error.localizedDescription)")
            }
        }
    }
}
#endif
