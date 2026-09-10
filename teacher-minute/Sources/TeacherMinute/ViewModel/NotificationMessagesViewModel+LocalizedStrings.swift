//
//  NotificationMessagesViewModel+LocalizedStrings.swift
//  teacher-minute
//
//  Copy for the in-app messages inbox.
//

import Foundation

extension NotificationMessagesViewModel {
    var screenTitle: String { LocalizationSupport.localized("Messages") }
    var loadingText: String { LocalizationSupport.localized("Loading messages") }
    var doneLabel: String { LocalizationSupport.localized("Done") }
    var emptyTitle: String { LocalizationSupport.localized("No messages") }
    var emptySubtitle: String {
        LocalizationSupport.localized("New updates and personal messages will appear here.")
    }

    /// When a message was sent, e.g. "Sent 4 Jun 2026 at 09:41".
    func sentText(_ timestamp: Date) -> String {
        guard timestamp > .distantPast else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = LocalizationSupport.currentLocale
        return String(format: LocalizationSupport.localized("Sent %@"),
                      formatter.string(from: timestamp))
    }
}
