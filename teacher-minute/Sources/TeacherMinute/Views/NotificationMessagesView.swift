import SwiftUI

struct NotificationMessagesView: View {
    @State var viewModel = NotificationMessagesViewModel()
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(theme.appPink)
                        Text("Loading messages")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.appSecondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                NotificationMessageRow(message: message) {
                                    viewModel.delete(message)
                                }
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(LocalizationSupport.localized("Messages"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.loadMessages()
            }
            .refreshable {
                await viewModel.loadMessages()
            }
        }
        .trackScreen(AnalyticsScreen.notificationMessages)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(theme.appGrayBackground)
                .frame(width: 74, height: 74)
                .overlay {
                    PlatformIcon(
                        systemName: "bell.fill",
                        size: 28,
                        weight: .semibold,
                        color: theme.appSecondaryText
                    )
                }

            Text("No messages")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.appPrimaryText)

            Text("New updates and personal messages will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(theme.appSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NotificationMessageRow: View {
    let message: NotificationMessage
    let deleteAction: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        RoundedInfoCard {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(message.isRead ? theme.appGrayBackground : theme.appPinkSoft)
                    .frame(width: 42, height: 42)
                    .overlay {
                        PlatformIcon(
                            systemName: message.isRead ? "envelope.open.fill" : "envelope.fill",
                            size: 17,
                            weight: .semibold,
                            color: message.isRead ? theme.appSecondaryText : theme.appPink
                        )
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(message.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.appPrimaryText)
                            .lineLimit(2)

                        Spacer()

                        if !message.isRead {
                            Circle()
                                .fill(theme.appPink)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.appSecondaryText)
                        .lineSpacing(3)

                    Text(dateText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.appSecondaryText)
                }

                Button(action: deleteAction) {
                    PlatformIcon(
                        systemName: "trash.fill",
                        size: 13,
                        weight: .semibold,
                        color: theme.appSecondaryText
                    )
                    .frame(width: 30, height: 30)
                    .background(theme.appGrayBackground)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var dateText: String {
        guard message.timestamp > .distantPast else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Sent \(formatter.string(from: message.timestamp))"
    }
}

#if os(iOS)
struct NotificationMessagesView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationMessagesView()
    }
}
#endif
