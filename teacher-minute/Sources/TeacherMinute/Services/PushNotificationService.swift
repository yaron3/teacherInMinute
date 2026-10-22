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

    /// The invite whose notification the teacher tapped, held until the
    /// dashboard is there to take it — on a cold launch the tap arrives well
    /// before the teacher's dashboard exists.
    private var tappedInviteQuestionId: String?

    /// Set by the teacher dashboard. Receives a tapped invite at once, or the
    /// one tapped before it was set.
    var onInviteTapped: ((String) -> Void)? {
        didSet { deliverTappedInvite() }
    }

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

    /// Tapping an invite's notification is the teacher taking the question.
    /// Called by the iOS notification delegate, and on Android by the
    /// dashboard's poll of MainActivity.
    func inviteNotificationTapped(questionId: String) {
        logger.info("[Push] invite notification tapped qid=\(questionId)")
        tappedInviteQuestionId = questionId
        deliverTappedInvite()
    }

    private func deliverTappedInvite() {
        guard let questionId = tappedInviteQuestionId, let onInviteTapped else { return }
        tappedInviteQuestionId = nil
        onInviteTapped(questionId)
    }

    func registerCurrentDevice(role: AppUserMode) {
        guard let uid = Auth.auth().currentUser?.uid else {
            logger.info("[Push] registerCurrentDevice ABORTED — no current Firebase user")
            return
        }
        registeredUID = uid
        registeredRole = role
	  logger.info("[Push] registerCurrentDevice uid=\(uid) role=\(role.rawValue)")

        Task {
            // Do NOT prompt here. Notification permission is requested only after
            // the student's first lesson, behind a custom explanation. We only
            // register the device token if permission has already been granted;
            // otherwise we defer until a later `registerCurrentDevice` call once
            // the user has granted it.
            let state = await PermissionService.shared.notificationStatus()
            logger.info("[Push] notification permission state=\(state.rawValue)")
            guard state == .granted else {
                logger.info("[Push] notifications not granted — deferring token registration")
                return
            }
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
            logger.error("[Push] ❌ FCM token registration failed: \(error.localizedDescription)")
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
    /// The `type` of the teacher invite push (functions/src/fcm.ts).
    nonisolated static let inviteType = "incoming_question"

    /// The identifier prefix both the invite push (its `apns-collapse-id`) and
    /// LocalNotificationService give an invite notification.
    nonisolated static let inviteIdentifierPrefix = "teacher-question-"

    /// Clears invite notifications. Called when the app comes to the front:
    /// from then on the in-app overlay is how an invite is answered, and one
    /// left in Notification Center outlives the invite it offers. Mirrors
    /// AndroidIncomingQuestionNotifier.cancelAll.
    public func clearInviteNotifications() {
        Task {
            let center = UNUserNotificationCenter.current()
            let ids = await center.deliveredNotifications()
                .map(\.request)
                .filter {
                    $0.identifier.hasPrefix(Self.inviteIdentifierPrefix)
                        || $0.content.userInfo["type"] as? String == Self.inviteType
                }
                .map(\.identifier)
            guard !ids.isEmpty else { return }
            center.removeDeliveredNotifications(withIdentifiers: ids)
            logger.info("[Push] cleared \(ids.count) invite notification(s)")
        }
    }

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
        // In the foreground the dashboard already raises the invite overlay
        // from RTDB, so a banner would announce the same invite twice.
        if notification.request.content.userInfo["type"] as? String == Self.inviteType {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound, .badge, .list])
    }

    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let type = userInfo["type"] as? String ?? "unknown"
        // The invite push carries `questionId`; the local notification posted
        // for the same invite (LocalNotificationService) only its identifier.
        let identifier = response.notification.request.identifier
        let inviteQuestionId = userInfo["questionId"] as? String
            ?? (identifier.hasPrefix(Self.inviteIdentifierPrefix)
                ? String(identifier.dropFirst(Self.inviteIdentifierPrefix.count))
                : nil)
        let isInvite = type == Self.inviteType || identifier.hasPrefix(Self.inviteIdentifierPrefix)
        let isDefaultAction = response.actionIdentifier == UNNotificationDefaultActionIdentifier
        Task { @MainActor in
            logger.info("[Push] tapped notification type=\(type)")
            AnalyticsService.shared.logEvent(AnalyticsEvent.notificationOpened, parameters: ["type": type])
            // Only the tap itself takes the question, not dismissing it.
            if isInvite, isDefaultAction, let inviteQuestionId, !inviteQuestionId.isEmpty {
                self.inviteNotificationTapped(questionId: inviteQuestionId)
            }
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
                logger.error("[Push] ❌ FCM token refresh write failed: \(error.localizedDescription)")
            }
        }
    }
}
#endif
