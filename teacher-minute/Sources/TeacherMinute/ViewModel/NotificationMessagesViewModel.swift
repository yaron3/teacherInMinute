import Foundation
import Observation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

@Observable
@MainActor
final class NotificationMessagesViewModel {
    var messages: [NotificationMessage] = []
    var isLoading = true
    var errorMessage: String?

    var isEmpty: Bool {
        !isLoading && messages.isEmpty
    }

    func loadMessages() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            messages = try await NotificationMessageService.shared.fetchMessages(uid: uid)
            await markVisibleMessagesRead(uid: uid)
        } catch {
            errorMessage = "Could not load messages."
            logger.error("[Messages] failed loading messages: \(error.localizedDescription)")
        }
    }

    func delete(_ message: NotificationMessage) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        messages.removeAll { $0.id == message.id }

        Task {
            do {
                try await NotificationMessageService.shared.delete(message, uid: uid)
            } catch {
                errorMessage = "Could not delete message."
                logger.error("[Messages] failed deleting message: \(error.localizedDescription)")
                await loadMessages()
            }
        }
    }

    private func markVisibleMessagesRead(uid: String) async {
        let unreadMessages = messages.filter { !$0.isRead }
        guard !unreadMessages.isEmpty else { return }

        for message in unreadMessages {
            do {
                try await NotificationMessageService.shared.markRead(message, uid: uid)
            } catch {
                logger.error("[Messages] failed marking read: \(error.localizedDescription)")
            }
        }
    }
}
