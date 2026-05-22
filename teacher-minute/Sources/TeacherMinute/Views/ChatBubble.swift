import SwiftUI

struct ChatBubble: View {
  let message: ChatMessage
  let timeText: String
  let avatarImageURL: String
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      if message.isMine { Spacer(minLength: 54) }

      if !message.isMine {
        avatar
      }

      VStack(alignment: message.isMine ? .trailing : .leading, spacing: 5) {
        if ChatBubble.isLatex(message.text) {
          MathFormulaView(latex: message.text, displayMode: true)
            .frame(minWidth: 160, maxWidth: 280, minHeight: 70)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(theme.appCardBackground)
            .overlay(
              RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(message.isMine ? theme.appPink : theme.appBorder.opacity(0.5), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        } else {
          Text(message.text)
            .font(.system(size: 14))
            .foregroundStyle(message.isMine ? theme.appCardBackground: theme.appPrimaryText)
            .lineSpacing(3)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(message.isMine ? theme.appPink : theme.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }

        Text(timeText)
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(theme.appSecondaryText)
      }

      if message.isMine {
        avatar
      }

      if !message.isMine { Spacer(minLength: 54) }
    }
  }

  var avatar: some View {
    ProfileAvatarView(
      imageURL: avatarImageURL,
      size: 24,
      fallbackSystemImage: "person.crop.circle.fill",
      background: message.isMine ? theme.appPurpleSoft : theme.appGreenSoft,
      tint: message.isMine ? theme.appPurple : theme.appGreen
    )
  }

  static func isLatex(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    let markers = ["\\frac", "\\sqrt", "\\pi", "\\int", "\\sum", "\\times", "\\div", "^{", "_{"]
    for marker in markers where trimmed.contains(marker) {
      return true
    }
    return false
  }
}
