//
//  PayoutMethodTypePicker.swift
//  teacher-minute
//
// The "where should the money go" tab strip, shared by the payout form
// (TeacherPayoutMethodSheet) and the profile-completion step — the tab a
// teacher picks while onboarding is then literally the same control, already
// on that tab, when they come to type the details.

import SwiftUI

struct PayoutMethodTypePicker: View {
  /// Which destinations to offer. PayPal is gated behind a Remote Config flag,
  /// so this is not always every `PayoutMethodType`.
  let types: [PayoutMethodType]
  /// `nil` renders with no tab selected — the profile step lets a teacher
  /// answer none of them for now.
  let selected: PayoutMethodType?
  let onSelect: (PayoutMethodType) -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(types) { type in
        tab(type)
      }
    }
    .padding(3)
    .background(theme.cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
  }

  func tab(_ type: PayoutMethodType) -> some View {
    let isSelected = selected == type
    // The selected tab sits on the saturated `accent` fill, so its label needs
    // a colour that stays light in both schemes. `onAccentText` is not it: its
    // light value is black, which leaves near-unreadable dark text on indigo.
    let selectedForeground = theme.ctaForeground
    return Button {
      onSelect(type)
    } label: {
      HStack(spacing: 6) {
        PlatformIcon(
          systemName: type.systemImage,
          size: 13,
          weight: .semibold,
          color: isSelected ? selectedForeground : theme.secondaryText
        )
        Text(type.displayName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(isSelected ? selectedForeground : theme.secondaryText)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .padding(.vertical, 10)
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity)
      .background(isSelected ? theme.accent : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}
