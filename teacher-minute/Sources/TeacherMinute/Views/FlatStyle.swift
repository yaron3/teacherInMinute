//
//  FlatStyle.swift
//  teacher-minute
//
//  The flat components screens are built from, in the brand's style: cards
//  translucent over the dark gradient with the violet outline, cyan actions,
//  white titles. Colors come from `AppTheme`; this file only holds the shared
//  metrics and the components built on them.
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

/// Grouping panel: the brand's card, translucent over the gradient, with the
/// violet outline. `outlined` leaves the fill out, for a list whose rows
/// stand on the gradient themselves; `filled` tints it instead.
struct FlatCard<Content: View>: View {
  let content: Content
  var padding: CGFloat = 16
  var outlined = false
  /// Overrides the translucent fill — used for the tinted promo panel.
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
      .background(filled ?? (outlined ? Color.clear : theme.brandCardSurface))
      .clipShape(RoundedRectangle(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16)
          .stroke(theme.brandControlBorder, lineWidth: 1)
      }
  }
}

/// Small capsule chip — a subject, a count, a quiet action. `outlined` leaves
/// the fill out, for a chip that sits on a card.
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
        PlatformIcon(systemName: systemImage, size: 13, weight: .medium, color: theme.brandActionBackground)
      }
      Text(title)
        .font(.system(size: 14, weight: .medium))
        .foregroundStyle(theme.onDarkFill)
    }
    .padding(.horizontal, 14)
    .frame(height: 36)
    .background(outlined ? Color.clear : theme.brandCardSurface)
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .stroke(theme.brandControlBorder, lineWidth: flatHairline)
    }
  }
}

/// Solid badge for short status text — the `NEW` treatment: cyan, black text.
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
      .foregroundStyle(foreground ?? theme.onBrandAction)
      .padding(.horizontal, 8)
      .frame(height: 24)
      .background(background ?? theme.brandActionBackground)
      .clipShape(RoundedRectangle(cornerRadius: flatRadiusBadge, style: .continuous))
  }
}

/// Rounded square holding a single icon — the leading element on list rows.
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
      .fill(background ?? theme.brandActionBackground.opacity(0.12))
      .frame(width: size, height: size)
      .overlay {
        PlatformIcon(systemName: systemName, size: size * 0.4, weight: .medium, color: tint ?? theme.brandActionBackground)
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
      .fill(theme.brandControlBorder)
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

/// Primary action: the brand's cyan, with a black label.
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
            color: foreground ?? theme.onBrandAction
          )
        }
        Text(title)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(foreground ?? theme.onBrandAction)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .background(background ?? theme.brandActionBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .tappableFrame()
    }
    .buttonStyle(.plain)
  }
}

/// Secondary action: the same geometry, outlined in cyan.
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
          PlatformIcon(systemName: systemImage, size: 15, weight: .bold, color: theme.brandActionBackground)
        }
        Text(title)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(theme.brandActionBackground)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity)
      .frame(height: 52)
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(theme.brandActionBackground, lineWidth: 1)
      }
      .tappableFrame()
    }
    .buttonStyle(.plain)
  }
}

/// Search field, in the brand's field style.
struct FlatSearchField: View {
  let placeholder: String
  @Binding var text: String

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "magnifyingglass")
        .resizable()
        .scaledToFit()
        .foregroundStyle(theme.brandSecondaryText)
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)

      TextField("", text: $text, prompt: Text(placeholder).foregroundColor(theme.brandSecondaryText))
        .textFieldStyle(.plain)
        .font(.system(size: 16))
        .foregroundStyle(theme.onDarkFill)
        .tint(theme.brandActionBackground)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
    }
    .padding(.horizontal, 12)
    .frame(height: textFieldContainerHeight(52))
    .background(theme.brandBackgroundTop)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
  }
}

/// Large page title, as a brand page's hero draws it.
struct FlatPageTitle: View {
  let title: String

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Text(title)
      .font(.system(size: 34, weight: .bold))
      .foregroundStyle(theme.onDarkFill)
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
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
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

/// The bell that opens the messages sent to the user, in a section's header
/// beside the menu button, with a dot when there is something unread.
struct BrandMessagesButton: View {
  var showsBadge = false
  var onMessagesDismissed: (() -> Void)?

  @State var showsMessages = false
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button {
      showsMessages = true
    } label: {
      Image(systemName: "bell")
        .resizable()
        .scaledToFit()
        .foregroundStyle(theme.brandActionBackground)
        .frame(width: 20, height: 20)
        .frame(width: 44, height: 44)
        .background(theme.brandActionBackground.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(theme.brandControlBorder, lineWidth: 1)
        }
        .overlay(alignment: .topTrailing) {
          if showsBadge {
            BrandBadgeDot()
              .padding(5)
          }
        }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("messages_button")
    .sheet(isPresented: $showsMessages, onDismiss: {
      onMessagesDismissed?()
    }) {
      NotificationMessagesView()
    }
  }
}
