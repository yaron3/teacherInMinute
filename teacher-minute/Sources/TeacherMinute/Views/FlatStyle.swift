//
//  FlatStyle.swift
//  teacher-minute
//
//  Flat design layer: solid colors, no gradients, no shadows.
//  Structure comes from filled gray panels and large type weight rather than
//  shadows or outlines. Colors come from `AppTheme`; this file only holds the
//  shared metrics and the components built on them.
//

import SwiftUI

/// Radius scale. Panels and buttons share one step; icon tiles and badges step
/// down. Small chips use a full capsule instead.
let flatRadius: CGFloat = 14
let flatRadiusSmall: CGFloat = 10
let flatRadiusBadge: CGFloat = 6

/// The height to give a container wrapping a `TextField`.
///
/// Skip composes `TextField` as a Material `OutlinedTextField`, which lays
/// itself out at its own 56dp minimum and lets the parent's clip cut whatever
/// does not fit. A shorter container therefore crops the descenders off
/// letters like "j", "g" and "p" — "Search subjects or subtopics" rendered as
/// "Search subiects or subtopics". iOS has no such floor, so it keeps the
/// design's height.
func textFieldContainerHeight(_ designHeight: CGFloat) -> CGFloat {
#if os(Android)
    max(designHeight, 56)
#else
    designHeight
#endif
}
let flatHairline: CGFloat = 1

// MARK: - Components

/// Grouping panel. Filled gray and borderless by default; `outlined` gives the
/// white-with-hairline variant used for row lists.
struct FlatCard<Content: View>: View {
  let content: Content
  var padding: CGFloat = 16
  var outlined = false
  /// Overrides the default raised gray — used for the tinted promo panel.
  var filled: Color?

  init(padding: CGFloat = 16, outlined: Bool = false, filled: Color? = nil, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.outlined = outlined
    self.filled = filled
    self.content = content()
  }

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    content
      .padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(filled ?? (outlined ? theme.screenBackground : theme.cardBackground))
      .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
      .overlay {
        if outlined {
          RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
            .stroke(theme.separator, lineWidth: flatHairline)
        }
      }
  }
}

/// Small capsule chip — the `Later` / `FAQs` / `Take a tour` treatment.
/// Use `outlined` when the chip sits on a filled card, where a gray fill would
/// disappear into the card behind it.
struct FlatChip: View {
  let title: String
  var systemImage: String?
  var outlined = false

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack(spacing: 6) {
      if let systemImage {
        PlatformIcon(systemName: systemImage, size: 13, weight: .medium, color: theme.primaryText)
      }
      Text(title)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(theme.primaryText)
    }
    .padding(.horizontal, 14)
    .frame(height: 36)
    .background(outlined ? theme.screenBackground : theme.cardBackground)
    .clipShape(Capsule())
    .overlay {
      if outlined {
        Capsule()
          .stroke(theme.separator, lineWidth: flatHairline)
      }
    }
  }
}

/// Solid badge for short status text — the `NEW` treatment.
struct FlatBadge: View {
  let title: String
  var foreground: Color?
  var background: Color?

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Text(title)
      .font(.system(size: 12, weight: .bold))
      .foregroundStyle(foreground ?? theme.onAccentText)
      .padding(.horizontal, 8)
      .frame(height: 24)
      .background(background ?? theme.accent)
      .clipShape(RoundedRectangle(cornerRadius: flatRadiusBadge, style: .continuous))
  }
}

/// Rounded-square holding a single icon — the leading element on list rows.
/// Defaults to the raised gray; pass `background: theme.screenBackground` when the
/// tile sits on a filled card, otherwise it vanishes into the card behind it.
struct FlatIconTile: View {
  let systemName: String
  var size: CGFloat = 44
  var tint: Color?
  var background: Color?

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous)
      .fill(background ?? theme.cardBackground)
      .frame(width: size, height: size)
      .overlay {
        PlatformIcon(systemName: systemName, size: size * 0.4, weight: .medium, color: tint ?? theme.primaryText)
      }
  }
}

/// Full-bleed hairline rule.
struct FlatRule: View {
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Rectangle()
      .fill(theme.separator)
      .frame(height: flatHairline)
      .frame(maxWidth: .infinity)
  }
}

/// Small round status dot.
struct FlatStatusDot: View {
  let color: Color
  var size: CGFloat = 9

  var body: some View {
    Circle()
      .fill(color)
      .frame(width: size, height: size)
  }
}

/// Primary action: solid ink, inverse label, no shadow.
struct FlatPrimaryButton: View {
  let title: String
  var systemImage: String?
  var background: Color?
  var foreground: Color?
  let action: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let systemImage {
          PlatformIcon(
            systemName: systemImage,
            size: 15,
            weight: .bold,
            color: foreground ?? theme.onAccentText
          )
        }
        Text(title)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(foreground ?? theme.onAccentText)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(background ?? theme.accent)
      .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

/// Secondary action: same geometry, filled gray instead of ink.
struct FlatSecondaryButton: View {
  let title: String
  var systemImage: String?
  let action: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let systemImage {
          PlatformIcon(systemName: systemImage, size: 15, weight: .bold, color: theme.primaryText)
        }
        Text(title)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.primaryText)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(theme.cardBackground)
      .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

/// Gray filled search field — the `Where to?` treatment. No border, no shadow.
struct FlatSearchField: View {
  let placeholder: String
  @Binding var text: String

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack(spacing: 12) {
      PlatformIcon(systemName: "magnifyingglass", size: 17, weight: .medium, color: theme.secondaryText)

      TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 17))
        .foregroundStyle(theme.primaryText)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
    .padding(.horizontal, 16)
    .frame(height: textFieldContainerHeight(52))
    .background(theme.cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
  }
}

/// Round icon button — the circular header controls (filter, forward arrow).
struct FlatRoundButton: View {
  let systemName: String
  var size: CGFloat = 40
  let action: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button(action: action) {
      Circle()
        .fill(theme.cardBackground)
        .frame(width: size, height: size)
        .overlay {
          PlatformIcon(systemName: systemName, size: size * 0.4, weight: .medium, color: theme.primaryText)
        }
    }
    .buttonStyle(.plain)
  }
}

/// Large page title — the `Services` / `Activity` treatment.
struct FlatPageTitle: View {
  let title: String

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Text(title)
      .font(.system(size: 36, weight: .bold))
      .foregroundStyle(theme.primaryText)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Section heading used above each block.
struct FlatSectionHeader<Trailing: View>: View {
  let title: String
  let trailing: Trailing

  init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
    self.title = title
    self.trailing = trailing()
  }

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack {
      Text(title)
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.primaryText)
      Spacer()
      trailing
    }
  }
}

extension FlatSectionHeader where Trailing == EmptyView {
  init(_ title: String) {
    self.init(title) { EmptyView() }
  }
}

/// Flat counterpart of `AppTopHeader` — no shadow, no purple/orange accents,
/// bell sits in a gray circle the way Uber's round header controls do.
struct FlatTopHeader: View {
  let eyebrow: String
  let name: String
  var avatarImageURL = ""
  var avatarSystemImage = "person.crop.circle.fill"
  var showNotificationBadge = false
  var onMessagesDismissed: (() -> Void)?

  @State var showsMessages = false
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack(spacing: 12) {
      ProfileAvatarView(
        imageURL: avatarImageURL,
        size: 40,
        fallbackSystemImage: avatarSystemImage,
        background: theme.cardBackground,
        tint: theme.primaryText
      )

      VStack(alignment: .leading, spacing: 1) {
        Text(LocalizedStringKey(eyebrow))
          .font(.system(size: 13))
          .foregroundStyle(theme.secondaryText)

        Text(name)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.primaryText)
      }

      Spacer()

      Button {
        showsMessages = true
      } label: {
        ZStack(alignment: .topTrailing) {
          Circle()
            .fill(theme.cardBackground)
            .frame(width: 44, height: 44)
            .overlay {
              PlatformIcon(systemName: "bell", size: 17, weight: .medium, color: theme.primaryText)
            }

          if showNotificationBadge {
            Circle()
              .fill(theme.positive)
              .frame(width: 9, height: 9)
              .offset(x: 1, y: -1)
          }
        }
      }
      .buttonStyle(.plain)
    }
    .sheet(isPresented: $showsMessages, onDismiss: {
      onMessagesDismissed?()
    }) {
      NotificationMessagesView()
    }
  }
}
