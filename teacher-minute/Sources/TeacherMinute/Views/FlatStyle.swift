//
//  FlatStyle.swift
//  teacher-minute
//
//  Flat design layer: solid colors, no gradients, no shadows.
//  Structure comes from filled gray panels and large type weight rather than
//  shadows or outlines. Currently scoped to TeacherDashboardView so the rest of
//  the app keeps the existing card styling until the direction is confirmed.
//

import SwiftUI

// MARK: - Tokens

extension AppTheme {

  /// Page background. Pure white / pure black — no off-white tints.
  var flatSurface: Color {
    adaptive(
      light: (255, 255, 255),
      dark: (0, 0, 0)
    )
  }

  /// Filled panel. This is the default surface for cards and tiles — a solid
  /// light gray with no border, which is what carries grouping.
  var flatSurfaceRaised: Color {
    adaptive(
      light: (242, 242, 242),
      dark: (28, 28, 28)
    )
  }

  /// Hairline rule. Used only for row lists on a white card, not around tiles.
  var flatLine: Color {
    adaptive(
      light: (232, 232, 232),
      dark: (42, 42, 42)
    )
  }

  /// Primary text, and the fill for primary buttons.
  var flatInk: Color {
    adaptive(
      light: (0, 0, 0),
      dark: (255, 255, 255)
    )
  }

  /// Text drawn on top of `flatInk`.
  var flatInkInverse: Color {
    adaptive(
      light: (255, 255, 255),
      dark: (0, 0, 0)
    )
  }

  var flatInkMuted: Color {
    adaptive(
      light: (110, 110, 110),
      dark: (160, 160, 160)
    )
  }

  /// The one functional accent: online / ready / positive.
  var flatPositive: Color {
    adaptive(
      light: (0, 122, 71),
      dark: (34, 197, 94)
    )
  }

  /// Used sparingly for expiring timers and destructive edges.
  var flatCritical: Color {
    adaptive(
      light: (200, 30, 30),
      dark: (248, 113, 113)
    )
  }
}

/// Radius scale. Panels and buttons share one step; icon tiles and badges step
/// down. Small chips use a full capsule instead.
let flatRadius: CGFloat = 14
let flatRadiusSmall: CGFloat = 10
let flatRadiusBadge: CGFloat = 6
let flatHairline: CGFloat = 1

// MARK: - Components

/// Grouping panel. Filled gray and borderless by default; `outlined` gives the
/// white-with-hairline variant used for row lists.
struct FlatCard<Content: View>: View {
  let content: Content
  var padding: CGFloat = 16
  var outlined = false

  init(padding: CGFloat = 16, outlined: Bool = false, @ViewBuilder content: () -> Content) {
    self.padding = padding
    self.outlined = outlined
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
      .background(outlined ? theme.flatSurface : theme.flatSurfaceRaised)
      .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
      .overlay {
        if outlined {
          RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
            .stroke(theme.flatLine, lineWidth: flatHairline)
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
        PlatformIcon(systemName: systemImage, size: 13, weight: .medium, color: theme.flatInk)
      }
      Text(title)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(theme.flatInk)
    }
    .padding(.horizontal, 14)
    .frame(height: 36)
    .background(outlined ? theme.flatSurface : theme.flatSurfaceRaised)
    .clipShape(Capsule())
    .overlay {
      if outlined {
        Capsule()
          .stroke(theme.flatLine, lineWidth: flatHairline)
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
      .foregroundStyle(foreground ?? theme.flatInkInverse)
      .padding(.horizontal, 8)
      .frame(height: 24)
      .background(background ?? theme.flatInk)
      .clipShape(RoundedRectangle(cornerRadius: flatRadiusBadge, style: .continuous))
  }
}

/// Rounded-square holding a single icon — the leading element on list rows.
/// Defaults to the raised gray; pass `background: theme.flatSurface` when the
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
      .fill(background ?? theme.flatSurfaceRaised)
      .frame(width: size, height: size)
      .overlay {
        PlatformIcon(systemName: systemName, size: size * 0.4, weight: .medium, color: tint ?? theme.flatInk)
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
      .fill(theme.flatLine)
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
            color: foreground ?? theme.flatInkInverse
          )
        }
        Text(title)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(foreground ?? theme.flatInkInverse)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(background ?? theme.flatInk)
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
          PlatformIcon(systemName: systemImage, size: 15, weight: .bold, color: theme.flatInk)
        }
        Text(title)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.flatInk)
      }
      .frame(maxWidth: .infinity)
      .frame(height: 54)
      .background(theme.flatSurfaceRaised)
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
      PlatformIcon(systemName: "magnifyingglass", size: 17, weight: .medium, color: theme.flatInkMuted)

      TextField(placeholder, text: $text)
        .font(.system(size: 17))
        .foregroundStyle(theme.flatInk)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
    .padding(.horizontal, 16)
    .frame(height: 52)
    .background(theme.flatSurfaceRaised)
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
        .fill(theme.flatSurfaceRaised)
        .frame(width: size, height: size)
        .overlay {
          PlatformIcon(systemName: systemName, size: size * 0.4, weight: .medium, color: theme.flatInk)
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
      .foregroundStyle(theme.flatInk)
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
        .foregroundStyle(theme.flatInk)
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
        background: theme.flatSurfaceRaised,
        tint: theme.flatInk
      )

      VStack(alignment: .leading, spacing: 1) {
        Text(LocalizedStringKey(eyebrow))
          .font(.system(size: 13))
          .foregroundStyle(theme.flatInkMuted)

        Text(name)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.flatInk)
      }

      Spacer()

      Button {
        showsMessages = true
      } label: {
        ZStack(alignment: .topTrailing) {
          Circle()
            .fill(theme.flatSurfaceRaised)
            .frame(width: 44, height: 44)
            .overlay {
              PlatformIcon(systemName: "bell", size: 17, weight: .medium, color: theme.flatInk)
            }

          if showNotificationBadge {
            Circle()
              .fill(theme.flatPositive)
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
