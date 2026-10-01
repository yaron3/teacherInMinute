import SwiftUI

// The frame of a running lesson, as the design draws it: a toggle between the
// chat and the board across the top, the lesson's clock, its two people and its
// medium across the bottom, and a mascot that says what is going on.
//
// Everything here is handed what it shows. The strings come from the view
// model through `ChatSessionView`, and the actions go back to it.

// MARK: - Top

/// One pane the lesson can show, as a segment of `SessionTabToggle`.
struct SessionToggleItem: Identifiable {
  let id: ChatSessionView.TAB_TYPE
  let title: String
  /// An asset in the module's catalog, drawn as a template.
  let iconName: String
  /// Something new has happened on this pane while it was not showing.
  let showsBadge: Bool
}

/// The Chat | Board switch. 266pt wide as designed, and narrower only where a
/// third pane (the question's photos) has to fit beside the two.
struct SessionTabToggle: View {
  let items: [SessionToggleItem]
  let selected: ChatSessionView.TAB_TYPE
  let onSelect: (ChatSessionView.TAB_TYPE) -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack(spacing: 4) {
      ForEach(items) { item in
        segment(item)
      }
    }
    .padding(4)
    .frame(maxWidth: 266)
    .background(theme.brandBackgroundTop)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
  }

  func segment(_ item: SessionToggleItem) -> some View {
    let isSelected = item.id == selected
    return Button {
      onSelect(item.id)
    } label: {
      HStack(spacing: 9) {
        Image(item.iconName, bundle: .module)
          .renderingMode(.template)
          .resizable()
          .frame(width: 24, height: 24)
        Text(item.title)
          .font(.system(size: 15, weight: .medium))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .foregroundStyle(isSelected ? theme.onBrandAction : theme.onDarkFill)
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .background(isSelected ? theme.brandActionBackground : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 10))
      .overlay(alignment: .leading) {
        if item.showsBadge {
          Circle()
            .fill(theme.brandDestructive)
            .frame(width: 6, height: 6)
            .padding(.leading, 12)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("session_tab_\(item.id.rawValue.lowercased())")
  }
}

/// The square button that closes the lesson: a red close mark on the brand's
/// cyan tint.
struct SessionCloseButton: View {
  let accessibilityLabel: String
  let action: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button {
      action()
    } label: {
      Image("brand-close-circle", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.brandDestructive)
        .frame(width: 22, height: 22)
        .frame(width: 44, height: 44)
        .background(theme.brandActionBackground.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(theme.brandActionBackground, lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
#if !os(Android)
    // SkipUI has no string `accessibilityLabel`.
    .accessibilityLabel(accessibilityLabel)
#endif
    .accessibilityIdentifier("session_end_button")
  }
}

/// The toggle and the close button. The toggle leads, so in Hebrew it stands
/// on the right and the close button on the left, as designed.
struct SessionTopBar: View {
  let items: [SessionToggleItem]
  let selected: ChatSessionView.TAB_TYPE
  let closeAccessibilityLabel: String
  let onSelect: (ChatSessionView.TAB_TYPE) -> Void
  let onClose: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      SessionTabToggle(items: items, selected: selected, onSelect: onSelect)
      Spacer(minLength: 0)
      SessionCloseButton(accessibilityLabel: closeAccessibilityLabel, action: onClose)
    }
    .padding(.horizontal, 24)
    .padding(.top, 4)
    .padding(.bottom, 20)
  }
}

// MARK: - Bottom

/// A small round mark on the line that joins the two people: a microphone
/// that is open or muted, a camera that is on or off.
struct SessionStatusBadge: Identifiable {
  enum Kind {
    case mic
    case micOff
    case video
    case videoOff
  }

  let id: String
  let kind: Kind

  var iconName: String {
    switch kind {
    case .mic: return "session-mic"
    case .micOff: return "session-mic-off"
    case .video: return "session-video"
    case .videoOff: return "session-video-off"
    }
  }

  var isOn: Bool { kind == .mic || kind == .video }
}

/// One of the two people in the lesson.
struct SessionIdentity: Identifiable {
  let id: String
  let imageURL: String
  let name: String
  let subtitle: String
  /// In the lesson right now; amber while their connection is lost.
  let isLive: Bool
  /// What this person's microphone and camera are doing.
  var badges: [SessionStatusBadge] = []
}

/// The width a person's column takes, and the gap between two of them.
private let sessionIdentityWidth: CGFloat = 56
private let sessionIdentityGap: CGFloat = 5

/// A bracket over two people, from the middle of one to the middle of the
/// other, that their badges sit on.
private struct SessionBracket: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 8))
    path.addQuadCurve(to: CGPoint(x: rect.minX + 8, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + 8), control: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    return path
  }
}

struct SessionPeople: View {
  let identities: [SessionIdentity]
  /// Draw the bracket and badges: only a lesson with audio has anything to say.
  let showsBadges: Bool

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: sessionIdentityGap) {
      ForEach(identities) { identity in
        identityColumn(identity)
      }
    }
    .overlay(alignment: .top) {
      if showsBadges {
        bracket
      }
    }
  }

  func identityColumn(_ identity: SessionIdentity) -> some View {
    VStack(spacing: 0) {
      ProfileAvatarView(
        imageURL: identity.imageURL,
        size: 38,
        fallbackSystemImage: "person.crop.circle.fill",
        background: theme.accentBackground,
        tint: theme.brandActionBackground
      )
      .overlay {
        Circle().stroke(theme.brandControlBorder, lineWidth: 1)
      }
      .overlay(alignment: .trailing) {
        Circle()
          .fill(identity.isLive ? theme.brandLive : theme.brandPaused)
          .frame(width: 6, height: 6)
          .offset(x: 1)
      }
      .padding(.bottom, 2)

      Text(identity.name)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Text(identity.subtitle)
        .font(.system(size: 11))
        .foregroundStyle(theme.brandSecondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(width: sessionIdentityWidth)
  }

  /// The line over the people. It starts 24pt above their portraits, where the
  /// badges ride on it, and drops to the middle of each.
  var bracket: some View {
    ZStack(alignment: .top) {
      SessionBracket()
        .stroke(theme.brandActionBackground.opacity(0.47), lineWidth: 2)
        .frame(width: sessionIdentityWidth + sessionIdentityGap, height: 24)
      HStack(spacing: 0) {
        ForEach(identities) { identity in
          HStack(spacing: 2) {
            ForEach(identity.badges) { badge in
              badgeView(badge)
            }
          }
          .frame(width: sessionIdentityWidth + sessionIdentityGap)
        }
      }
      .offset(y: -12)
    }
    .offset(y: -24)
    .frame(width: sessionIdentityWidth * 2 + sessionIdentityGap)
  }

  func badgeView(_ badge: SessionStatusBadge) -> some View {
    Image(badge.iconName, bundle: .module)
      .renderingMode(.template)
      .resizable()
      .foregroundStyle(theme.onBrandAction)
      .frame(width: 15, height: 15)
      .frame(width: 25, height: 25)
      .background(badge.isOn ? theme.brandLive : theme.brandPaused)
      .clipShape(Circle())
  }
}

/// The lesson's clock.
struct SessionTimer: View {
  let timeText: String
  let label: String

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    VStack(spacing: 0) {
      Text(timeText)
        .font(.system(size: 20, weight: .bold, design: .monospaced))
        .foregroundStyle(theme.onDarkFill)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
      Text(label)
        .font(.system(size: 14))
        .foregroundStyle(theme.brandSecondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .accessibilityIdentifier("session_timer")
  }
}

/// The mascot, with a speech bubble when there is something to say.
struct SessionMascot: View {
  let message: String?
  /// How much of the design's size to draw: 1 on a 402pt screen.
  let scale: CGFloat

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    // The bubble comes first, so it stands on the side the people do.
    HStack(alignment: .bottom, spacing: -36 * scale) {
      if let message {
        bubble(message)
          .padding(.bottom, 17 * scale)
      }
      Image("session-mascot", bundle: .module)
        .resizable()
        .scaledToFit()
        .frame(width: 98 * scale, height: 98 * scale)
        .accessibilityHidden(true)
    }
  }

  func bubble(_ message: String) -> some View {
    Image("session-bubble", bundle: .module)
      .resizable()
      .scaledToFit()
      .frame(width: 100 * scale, height: 100 * scale)
      .overlay {
        Text(message)
          .font(.system(size: 12, weight: .regular))
          .foregroundStyle(theme.onBrandAction)
          .multilineTextAlignment(.center)
          .lineLimit(4)
          .minimumScaleFactor(0.6)
          .frame(width: 62 * scale, height: 56 * scale)
          .offset(y: -6 * scale)
      }
      .accessibilityIdentifier("session_mascot_message")
  }
}

/// What a button in the media pill does.
struct SessionMediaAction: Identifiable {
  let id: String
  let iconName: String
  let isOn: Bool
  let accessibilityIdentifier: String
  let action: () -> Void
}

/// The button that opens the lesson's medium, and the pill that grows from it.
struct SessionMediaControl: View {
  /// "Media:" and the medium's name.
  let label: String
  let value: String
  /// Buttons of the pill, top to bottom. Empty for a text lesson, which has
  /// only the picker to open.
  let actions: [SessionMediaAction]
  @Binding var isExpanded: Bool
  /// Opens the picker that switches the lesson between text, audio and video.
  let onPickType: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    VStack(spacing: 2) {
      if isExpanded && !actions.isEmpty {
        pill
      } else {
        optionsButton
      }
      Button {
        onPickType()
      } label: {
        HStack(spacing: 2) {
          Text(label)
            .foregroundStyle(theme.brandSecondaryText)
          Text(value)
            .foregroundStyle(theme.onDarkFill)
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(width: 60)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("session_type_change")
    }
    .frame(width: 60)
  }

  var optionsButton: some View {
    Button {
      if actions.isEmpty {
        onPickType()
      } else {
        isExpanded = true
      }
    } label: {
      Image("session-options", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.onBrandAction)
        .frame(width: 16, height: 16)
        .frame(width: 38, height: 38)
        .background(theme.brandActionBackground)
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("session_media_options")
  }

  var pill: some View {
    VStack(spacing: 7) {
      ForEach(actions) { action in
        Button {
          action.action()
        } label: {
          Image(action.iconName, bundle: .module)
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(theme.onBrandAction)
            .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(action.accessibilityIdentifier)
      }
    }
    .padding(.vertical, 12)
    .frame(width: 38)
    .background(theme.brandActionBackground)
    .clipShape(RoundedRectangle(cornerRadius: 19))
    .overlay {
      RoundedRectangle(cornerRadius: 19)
        .stroke(theme.brandBackgroundTop, lineWidth: 1)
    }
  }
}

/// The strip along the bottom of a lesson.
///
/// Laid out leading to trailing — medium, the two people, the mascot, the
/// clock — which puts the medium at the right edge in Hebrew, as designed.
struct SessionBottomBar: View {
  let media: SessionMediaControl
  let people: SessionPeople
  let mascotMessage: String?
  let timer: SessionTimer
  /// Room the open media pill needs above the bar's own height.
  var extraHeight: CGFloat = 0

  var body: some View {
    GeometryReader { proxy in
      let scale = min(1, proxy.size.width / 402)
      HStack(alignment: .bottom, spacing: 8) {
        media
        people
        Spacer(minLength: 0)
        // The mascot's picture has room round it, so it may overlap the clock.
        SessionMascot(message: mascotMessage, scale: scale)
          .padding(.trailing, -18 * scale)
        timer
          .frame(width: 79 * scale)
      }
      .padding(.horizontal, 12)
      .padding(.bottom, 6)
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottom)
    }
    .frame(height: 72 + extraHeight)
  }
}

// MARK: - Composer

/// The message card at the foot of the chat: a send button, and a field with
/// the switch to the math pad inside it.
struct SessionMessageComposer: View {
  let placeholder: String
  let isFocused: FocusState<Bool>.Binding
  let onSend: (String) -> Void
  let onMath: () -> Void

  @State var draft = ""
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var canSend: Bool {
    !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var body: some View {
    HStack(spacing: 8) {
      sendButton
      field
    }
    .padding(12)
    .background(theme.brandModalBackground)
    .clipShape(RoundedRectangle(cornerRadius: 18))
    .overlay {
      RoundedRectangle(cornerRadius: 18)
        .stroke(theme.brandControlBorder.opacity(0.4), lineWidth: 1)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
  }

  var sendButton: some View {
    Button {
      send()
    } label: {
      Image("session-send", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.onBrandAction)
        .frame(width: 19, height: 19)
        .frame(width: 48, height: 48)
        .background(theme.brandActionBackground)
        .clipShape(Circle())
        .opacity(canSend ? 1 : 0.5)
    }
    .buttonStyle(.plain)
    .disabled(!canSend)
    .accessibilityIdentifier("chat_send_button")
  }

  var field: some View {
    HStack(spacing: 10) {
      TextField(placeholder, text: $draft)
        .focused(isFocused)
        .textFieldStyle(.plain)
        .font(.system(size: 14))
        .foregroundStyle(theme.onDarkFill)
        .lineLimit(1)
        .accessibilityIdentifier("chat_message_field")

      Button {
        onMath()
      } label: {
        Image("session-math", bundle: .module)
          .renderingMode(.template)
          .resizable()
          .foregroundStyle(theme.brandSecondaryText)
          .frame(width: 24, height: 24)
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("chat_math_button")
    }
    .padding(.horizontal, 12)
    .frame(height: 48)
    .background(Color(red: 32 / 255, green: 32 / 255, blue: 51 / 255))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
  }

  func send() {
    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    draft = ""
    onSend(text)
  }
}
