import SwiftUI

/// One message row.
///
/// The mapping from `ChatMessage` to `ChatBubble` lives here so the standalone
/// `ChatThreadView` and a thread laid out inline by a parent — see
/// `ChatSessionView.scrollingChatLayout` — cannot drift apart.
struct ChatThreadRow: View {
  let message: ChatMessage
  let now: Date
  let viewModel: any ChatSessionViewModeling

  var body: some View {
    ChatBubble(
      message: message,
      timeText: viewModel.messageTimeText(createdAt: message.createdAt, at: now),
      avatarImageURL: message.isMine ? viewModel.currentUserImageURL : viewModel.participantImageURL
    )
  }
}

/// The empty-thread hint, shared for the same reason as `ChatThreadRow`.
struct ChatThreadEmptyNotice: View {
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Text(LocalizationSupport.localized("Start with a text explanation, then use the board below for the math work."))
      .font(.system(size: 13))
      .foregroundStyle(theme.secondaryText)
      .multilineTextAlignment(.center)
      .padding(.horizontal, 28)
      .padding(.top, 24)
  }
}

struct ChatThreadView: View {
  let messages: [ChatMessage]
  let now: Date
  let viewModel: any ChatSessionViewModeling
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
    ScrollViewReader { proxy in
      // ScrollView + LazyVStack is the pairing Skip expects: on Android the
      // lazy stack *is* the scrolling LazyColumn, and it is what registers the
      // message ids that `scrollTo` needs. A plain stack scrolls but silently
      // ignores `scrollTo`.
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 8) {
          if messages.isEmpty {
            ChatThreadEmptyNotice()
          }

          ForEach(messages) { message in
            ChatThreadRow(message: message, now: now, viewModel: viewModel)
              .id(message.id)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
      }
      .background(theme.cardBackground.opacity(0.45))
      .onChange(of: messages.count) { _, _ in
        if let last = messages.last {
          withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(last.id, anchor: .bottom)
          }
        }
      }
    }
  }
}

#if os(iOS)
#Preview("with messages") {
    let vm = MockChatSessionViewModel(questionId: "abc", role: "teacher")
    ChatThreadView(messages: vm.messages, now: .init(), viewModel: vm)
}

#Preview("empty") {
    let vm = MockChatSessionViewModel(questionId: "abc", role: "student")
    ChatThreadView(messages: [], now: .init(), viewModel: vm)
}
#endif
