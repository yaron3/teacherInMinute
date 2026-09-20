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
                            .tint(theme.accent)
                        Text(viewModel.loadingText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.isEmpty {
                    emptyState
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                NotificationMessageRow(message: message,
                                                       dateText: viewModel.sentText(message.timestamp)) {
                                    viewModel.delete(message)
                                }
                            }
                        }
                        .padding(18)
                    }
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(viewModel.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(viewModel.doneLabel) { dismiss() }
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
                .fill(theme.cardBackground)
                .frame(width: 74, height: 74)
                .overlay {
                    PlatformIcon(
                        systemName: "bell.fill",
                        size: 28,
                        weight: .semibold,
                        color: theme.secondaryText
                    )
                }

            Text(viewModel.emptyTitle)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(theme.primaryText)

            Text(viewModel.emptySubtitle)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NotificationMessageRow: View {
    let message: NotificationMessage
    let dateText: String
    let deleteAction: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        RoundedInfoCard {
            HStack(alignment: .top, spacing: 12) {
                Circle()
                    .fill(message.isRead ? theme.cardBackground : theme.accentBackground)
                    .frame(width: 42, height: 42)
                    .overlay {
                        PlatformIcon(
                            systemName: message.isRead ? "envelope.open.fill" : "envelope.fill",
                            size: 17,
                            weight: .semibold,
                            color: message.isRead ? theme.secondaryText : theme.accent
                        )
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(message.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(2)

                        Spacer()

                        if !message.isRead {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 8, height: 8)
                        }
                    }

                    Text(message.text)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                        .lineSpacing(3)

                    Text(dateText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }

                Button(action: deleteAction) {
                    PlatformIcon(
                        systemName: "trash.fill",
                        size: 13,
                        weight: .semibold,
                        color: theme.secondaryText
                    )
                    .frame(width: 30, height: 30)
                    .background(theme.cardBackground)
                    .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#if os(iOS)
struct NotificationMessagesView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationMessagesView()
    }
}
#endif
