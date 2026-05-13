import SwiftUI

struct ChatBubble: View {
  let message: ChatMessage
  let timeText: String

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      if message.isMine { Spacer(minLength: 54) }

      if !message.isMine {
        avatar
      }

      VStack(alignment: message.isMine ? .trailing : .leading, spacing: 5) {
        Text(message.text)
          .font(.system(size: 14))
          .foregroundStyle(message.isMine ? .white : Color.appPrimaryText)
          .lineSpacing(3)
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
          .background(message.isMine ? Color.appPink : Color(red: 229 / 255, green: 231 / 255, blue: 235 / 255))
          .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

        Text(timeText)
          .font(.system(size: 9, weight: .medium))
          .foregroundStyle(Color.appSecondaryText)
      }

      if message.isMine {
        avatar
      }

      if !message.isMine { Spacer(minLength: 54) }
    }
  }

  var avatar: some View {
    Circle()
      .fill(message.isMine ? Color.appPurpleSoft : Color.appGreenSoft)
      .frame(width: 24, height: 24)
      .overlay {
        PlatformIcon(
          systemName: "person.crop.circle.fill",
          size: 18,
          weight: .semibold,
          color: message.isMine ? .appPurple : .appGreen
        )
      }
  }
}
