import SwiftUI

struct ChatInputBar: View {
  @Binding var text: String
  let isFocused: FocusState<Bool>.Binding
  let send: () -> Void

  var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        PlatformIcon(systemName: "photo.fill", size: 15, weight: .semibold, color: .appPrimaryText)
          .frame(width: 36, height: 36)
          .background(Color.appGrayBackground)
          .clipShape(Circle())

        TextField("Message", text: $text)
          .focused(isFocused)
          .textFieldStyle(.plain)
          .font(.system(size: 14))
          .lineLimit(1)
          .padding(.horizontal, 14)
          .frame(height: textFieldHeight)
          .background(Color.appGrayBackground)
          .clipShape(Capsule())

        Button {
          send()
        } label: {
          PlatformIcon(systemName: "paperplane.fill", size: 15, weight: .bold, color: .white)
            .frame(width: 42, height: 42)
            .background(
              LinearGradient(
                colors: canSend ? [Color.appPink, Color.appPurple] : [Color.appBorder, Color.appBorder],
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
              .foregroundStyle(Color.appPrimaryText)
              .frame(width: 34, height: 32)
              .background(Color.appGrayBackground)
              .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 2)
    }
  }
}
