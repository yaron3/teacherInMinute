import Foundation

#if !os(Android)
import UserNotifications
#else
import SkipBridge
#endif

@MainActor
final class LocalNotificationService {
    static let shared = LocalNotificationService()

    private var deliveredIdentifiers = Set<String>()

    private init() {}

    func scheduleTeacherQuestion(questionId: String, topic: String, text: String) {
        let body = topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? text : topic
        scheduleIfBackground(
            identifier: "teacher-question-\(questionId)",
            title: LocalizationSupport.localized("New Question"),
            body: body.isEmpty ? LocalizationSupport.localized("A student is waiting for help.") : body
        )
    }

    func scheduleChatMessage(questionId: String, message: ChatMessage, currentRole: String) {
        guard !message.isMine else { return }
        let sender = message.senderRole == "teacher"
            ? LocalizationSupport.localized("teacher")
            : LocalizationSupport.localized("student")
        let title = String(format: LocalizationSupport.localized("New message from %@"), sender)
        scheduleIfBackground(
            identifier: "chat-\(questionId)-\(message.id)",
            title: title,
            body: message.text.isEmpty ? LocalizationSupport.localized("Open the chat to view it.") : message.text
        )
    }

    func resetDeliveredCache() {
        deliveredIdentifiers.removeAll()
    }

    private func scheduleIfBackground(identifier: String, title: String, body: String) {
        guard !TeacherMinuteAppDelegate.shared.isInForeground else { return }
        guard deliveredIdentifiers.insert(identifier).inserted else { return }

#if os(Android)
        do {
            try AndroidLocalNotificationBridge.showNotification(identifier: identifier, title: title, body: body)
        } catch {
            logger.error("[LocalNotification] Android notification failed: \(error.localizedDescription)")
        }
#else
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral else {
                logger.info("[LocalNotification] skipped; notifications not authorized")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: identifier,
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                logger.error("[LocalNotification] iOS notification failed: \(error.localizedDescription)")
            }
        }
#endif
    }
}

#if os(Android)
private enum AndroidLocalNotificationBridge {
    private static let managerClass = try! JClass(name: "teacher/minute/AndroidLocalNotificationManager")
    private static let showNotificationMethod = managerClass.getStaticMethodID(
        name: "showNotification",
        sig: "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V"
    )!

    static func showNotification(identifier: String, title: String, body: String) throws {
        try jniContext {
            try managerClass.callStatic(
                method: showNotificationMethod,
                options: [.kotlincompat],
                args: [
                    identifier.toJavaParameter(options: [.kotlincompat]),
                    title.toJavaParameter(options: [.kotlincompat]),
                    body.toJavaParameter(options: [.kotlincompat])
                ]
            )
        }
    }
}
#endif
