import SwiftUI

struct NotificationMessagesView: View {
    @State var viewModel = NotificationMessagesViewModel()
    @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        // A plain stack around the sheet, which carries its modifiers; see
        // `BrandTabScreen`. `refreshable` reaches the sheet's scroll view
        // through the environment.
        ZStack {
            BrandSheet(title: viewModel.screenTitle, closeLabel: viewModel.doneLabel) {
                dismiss()
            } content: {
                if viewModel.isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(theme.onDarkFill)
                        Text(viewModel.loadingText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(theme.brandSecondaryText)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else if viewModel.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { message in
                            NotificationMessageRow(message: message,
                                                   dateText: viewModel.sentText(message.timestamp),
                                                   isExpanded: viewModel.isExpanded(message),
                                                   toggleAction: { viewModel.toggleExpanded(message) },
                                                   deleteAction: { viewModel.delete(message) })
                        }
                    }
                }
            }
        }
        // A sheet does not reliably inherit the app's chosen direction.
        .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
        .task {
            await viewModel.loadMessages()
        }
        .refreshable {
            await viewModel.loadMessages()
        }
        .trackScreen(AnalyticsScreen.notificationMessages)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(theme.accentBackground)
                .frame(width: 74, height: 74)
                .overlay {
                    Image(systemName: "bell")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(theme.brandActionBackground)
                        .frame(width: 28, height: 28)
                }

            Text(viewModel.emptyTitle)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.onDarkFill)

            Text(viewModel.emptySubtitle)
                .font(.system(size: 15))
                .foregroundStyle(theme.brandSecondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
    }
}

struct NotificationMessageRow: View {
    let message: NotificationMessage
    let dateText: String
    let isExpanded: Bool
    let toggleAction: () -> Void
    let deleteAction: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        RoundedInfoCard {
            HStack(alignment: .top, spacing: 12) {
                Button(action: { trackTap("notification_message_toggle", detail: message.id); toggleAction() }) {
                    HStack(alignment: .top, spacing: 12) {
                        envelope
                        messageText
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tappableFrame()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("notification_message_row")

                deleteButton
            }
        }
    }

    private var envelope: some View {
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
    }

    /// Two lines each while collapsed; everything once tapped.
    private var messageText: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleLine

            Text(message.text)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .lineSpacing(3)
                .lineLimit(isExpanded ? nil : 2)
                .multilineTextAlignment(.leading)

            HStack(spacing: 8) {
                Text(dateText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondaryText)

                Spacer()

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(message.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(isExpanded ? nil : 2)
                .multilineTextAlignment(.leading)

            Spacer()

            if !message.isRead {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var deleteButton: some View {
        Button(action: { trackTap("notification_message_delete", detail: message.id); deleteAction() }) {
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

#if os(iOS)
struct NotificationMessagesView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationMessagesView()
    }
}
#endif
