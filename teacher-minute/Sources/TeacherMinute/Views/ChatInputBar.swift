import SwiftUI

struct ChatInputBar: View {
  @Binding var text: String
  let isFocused: FocusState<Bool>.Binding
  let send: () -> Void

  var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var textFieldHeight: CGFloat {
#if os(Android)
    52
#else
    42
#endif
  }

  var body: some View {

      HStack(spacing: 10) {
		TextField(LocalizationSupport.localized("Message"), text: $text)
          .focused(isFocused)
          .textFieldStyle(.plain)
          .font(.system(size: 14))
          .lineLimit(1)
          .padding(.horizontal, 14)
          .frame(height: textFieldHeight)
          .background(theme.appGrayBackground)
          .clipShape(Capsule())

        Button {
          send()
        } label: {
          PlatformIcon(systemName: "paperplane.fill", size: 15, weight: .bold, color: theme.white)
            .frame(width: 42, height: 42)
            .background(
              LinearGradient(
                colors: canSend ? [theme.appPink, theme.appPurple] : [theme.appBorder, theme.appBorder],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
            )
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
    }
}
