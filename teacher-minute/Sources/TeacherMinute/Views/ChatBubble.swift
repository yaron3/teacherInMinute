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
        Text(message.text)
          .font(.system(size: 14))
          .foregroundStyle(message.isMine ? theme.appCardBackground: theme.appPrimaryText)
          .lineSpacing(3)
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
		  .background(message.isMine ? theme.appPink : theme.appCardBackground)
          .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

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
}
