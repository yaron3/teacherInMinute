import SwiftUI

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
      ScrollView(.vertical, showsIndicators: false) {
        LazyVStack(spacing: 8) {
          if messages.isEmpty {
            Text("Start with a text explanation, then use the board below for the math work.")
              .font(.system(size: 13))
              .foregroundStyle(theme.appSecondaryText)
              .multilineTextAlignment(.center)
              .padding(.horizontal, 28)
              .padding(.top, 24)
          }

          ForEach(messages) { message in
            ChatBubble(message: message, timeText: viewModel.messageTimeText(createdAt: message.createdAt, at: now))
              .id(message.id)
          }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
      }
      .background(theme.appGrayBackground.opacity(0.45))
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
struct ChatThreadView_Previews: PreviewProvider {
  static var previews: some View {
    let vm = MockChatSessionViewModel(questionId: "abc", role: "teacher", isConnecting: true)
    ChatThreadView(messages: [], now: .init(), viewModel: vm)
  }
}
#endif
