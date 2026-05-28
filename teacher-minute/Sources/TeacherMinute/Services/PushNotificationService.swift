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
	  logger.info("[Push] configureDelegates set UNUserNotificationCenter + MessagingDelegate")
    }
#else
    public func configureDelegates() {
	  logger.info("[Push] configureDelegates (Android no-op)")
    }
#endif

    func registerCurrentDevice(role: AppUserMode) {
        guard let uid = Auth.auth().currentUser?.uid else {
            logger.info("[Push] registerCurrentDevice ABORTED — no current Firebase user")
            return
        }
        registeredUID = uid
        registeredRole = role
	  logger.info("[Push] registerCurrentDevice uid=\(uid) role=\(role.rawValue)")

        Task {
            let state = await PermissionService.shared.requestNotifications()
            logger.info("[Push] notification permission state=\(state.rawValue)")
#if os(iOS)
            // APNS registration is async — the FCM token write happens later
            // in handleAPNSToken once the APNS token actually arrives.
            logger.info("[Push] calling UIApplication.registerForRemoteNotifications() — waiting for APNS callback")
            UIApplication.shared.registerForRemoteNotifications()
#else
            logger.info("[Push] Android path — writing FCM token directly")
            await writeCurrentToken(uid: uid, role: role)
#endif
        }
    }

    public func handleAPNSToken(_ token: Data) {
#if !os(Android)
        let hex = token.map { String(format: "%02x", $0) }.joined()
        logger.info("[Push] handleAPNSToken received apnsToken=\(hex.prefix(16))… (\(token.count) bytes)")
        Messaging.messaging().apnsToken = token
        guard let uid = registeredUID, let role = registeredRole else {
            logger.info("[Push] handleAPNSToken — no registered uid/role yet, FCM token will be written on next registerCurrentDevice")
            return
        }
        Task {
            await writeCurrentToken(uid: uid, role: role)
        }
#endif
    }

    private func writeCurrentToken(uid: String, role: AppUserMode) async {
        do {
            logger.info("[Push] requesting FCM token from Messaging.messaging().token()…")
            let token = try await Messaging.messaging().token()
            logger.info("[Push] got FCM token=\(token)")
            try await writeToken(token, uid: uid, role: role)
		  logger.info("[Push] ✅ FCM token written to RTDB uid=\(uid) role=\(role.rawValue)")
        } catch {
            logger.info("[Push] ❌ FCM token registration failed: \(error.localizedDescription)")
        }
    }

    private func writeToken(_ token: String, uid: String, role: AppUserMode) async throws {
#if !os(Android)
        let now = Date().timeIntervalSince1970 * 1000.0
        let deviceKey = Self.currentDeviceKey()
        let updates: [String: Any] = [
            "fcmToken": token,
            "fcmTokenUpdatedAt": now,
            "devices/\(deviceKey)/fcmToken": token,
            "devices/\(deviceKey)/token": token,
            "devices/\(deviceKey)/platform": "ios",
            "devices/\(deviceKey)/updatedAt": now
        ]

        logger.info("[Push] writing to users/\(uid) device=\(deviceKey)")
        try await setValues(updates, path: "users/\(uid)")
        if role == .teacher {
            logger.info("[Push] writing to teachers/\(uid) device=\(deviceKey)")
            try await setValues(updates, path: "teachers/\(uid)")
        }
#else
        logger.info("[Push] dispatching Android FCM token write uid=\(uid) isTeacher=\(role == .teacher)")
        AndroidPushTokenWriter.writeToken(token, uid: uid, isTeacher: role == .teacher)
#endif
    }

#if !os(Android)
    private static func currentDeviceKey() -> String {
#if os(iOS)
        if let identifier = UIDevice.current.identifierForVendor?.uuidString {
            return "ios-\(identifier)"
        }
#endif
        return "apple-device"
    }

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
        logger.info("[Push] MessagingDelegate didReceiveRegistrationToken fcmToken=\(fcmToken ?? "<nil>")")
        guard let fcmToken else { return }
        Task { @MainActor in
            guard let uid = self.registeredUID, let role = self.registeredRole else {
                logger.info("[Push] MessagingDelegate — token arrived but no registered uid/role yet, skipping write")
                return
            }
            do {
                try await self.writeToken(fcmToken, uid: uid, role: role)
                logger.info("[Push] ✅ refreshed FCM token written uid=\(uid)")
            } catch {
                logger.info("[Push] ❌ FCM token refresh write failed: \(error.localizedDescription)")
            }
        }
    }
}
#endif
