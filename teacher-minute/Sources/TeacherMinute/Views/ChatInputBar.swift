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
    VStack(spacing: 8) {
      if isFocused.wrappedValue {
        MathSymbolRow(text: $text, isFocused: isFocused)
      }

      HStack(spacing: 10) {
		TextField("Message", text: $text)
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
    .padding(.top, 10)
  }
}

struct MathSymbolRow: View {
  @Binding var text: String
  let isFocused: FocusState<Bool>.Binding

  private let mathSymbols = [
    "=", "+", "−", "×", "÷", "^", "√", "π", "∞", "≈", "≠", "≤", "≥", "∫", "∑", "θ", "α", "β"
  ]
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        ForEach(mathSymbols, id: \.self) { symbol in
          Button {
            text.append(symbol)
            isFocused.wrappedValue = true
          } label: {
            Text(symbol)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(theme.appPrimaryText)
              .frame(width: 34, height: 32)
              .background(theme.appGrayBackground)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 2)
    }
  }
}
