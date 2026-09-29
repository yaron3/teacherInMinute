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
    HStack(spacing: 8) {
      ForEach(types) { type in
        tab(type)
      }
    }
  }

  /// As the brand's option rows draw a choice: the chosen one outlined and
  /// named in cyan, the others in the muted outline.
  func tab(_ type: PayoutMethodType) -> some View {
    let isSelected = selected == type
    let tint = isSelected ? theme.brandActionBackground : theme.onDarkFill
    return Button {
      onSelect(type)
    } label: {
      HStack(spacing: 6) {
        PlatformIcon(
          systemName: type.systemImage,
          size: 13,
          weight: .semibold,
          color: tint
        )
        Text(type.displayName)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(tint)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .padding(.horizontal, 8)
      .frame(maxWidth: .infinity)
      .frame(height: 44)
      .overlay {
        RoundedRectangle(cornerRadius: 10)
          .stroke(isSelected ? theme.brandActionBackground : theme.brandOptionBorder, lineWidth: 1)
      }
      .tappableFrame()
    }
    .buttonStyle(.plain)
  }
}
