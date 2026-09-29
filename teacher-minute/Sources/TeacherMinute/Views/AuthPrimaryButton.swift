//
//  AuthPrimaryButton.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//
//  The form controls of the sign-in and onboarding steps, in the brand's
//  style: the call to action, the field, the header icon and the subject
//  chip.
//

import SwiftUI

/// The brand's call to action.
struct AuthPrimaryButton: View {
  let title: String
  var isEnabled = true
  let action: @MainActor () -> Void

  var body: some View {
    BrandPrimaryButton(title: title, isEnabled: isEnabled) {
      action()
    }
  }
}

/// The icon at the top of a form step, in a tinted square.
struct AuthIconHeader: View {
  let systemImage: String
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    RoundedRectangle(cornerRadius: 12)
      .fill(theme.brandActionBackground.opacity(0.12))
      .frame(width: 56, height: 56)
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(theme.brandControlBorder, lineWidth: 1)
      }
      .overlay {
        PlatformIcon(systemName: systemImage, size: 26, weight: .semibold, color: theme.brandActionBackground)
      }
  }
}

/// A labelled field: the brand's, with its icon where it has one.
struct AuthInputField: View {
  let title: String
  let placeholder: String
  let systemImage: String
  @Binding var text: String

  var keyboardType: UIKeyboardType = .default
  var textContentType: UITextContentType?
  var autocapitalization: TextInputAutocapitalization = .never
  /// False draws the field in the danger colour and shows `errorMessage`
  /// under it. Callers own the wording and decide when to start complaining —
  /// typically only once the field is non-empty, so it stays quiet while the
  /// number is still being typed.
  var isValid = true
  var errorMessage: String?

  var body: some View {
    BrandTextField(
      title: title,
      placeholder: placeholder,
      text: $text,
      icon: brandIcon,
      isValid: isValid,
      errorMessage: errorMessage ?? "",
      keyboardType: keyboardType,
      textContentType: textContentType,
      autocapitalization: autocapitalization
    )
  }

  /// The brand's icon for the field's symbol. The brand draws no others.
  var brandIcon: String? {
    switch systemImage {
    case "person", "person.fill": "brand-user"
    case "phone", "phone.fill": "brand-phone"
    case "lock", "lock.fill": "brand-lock"
    default: nil
    }
  }
}

/// A subject to teach: outlined, or filled cyan when chosen.
struct SubjectChip: View {
  let subject: SubjectOption
  let title: String
  let isSelected: Bool
  let action: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        PlatformIcon(
          systemName: subject.systemImage,
          size: 14,
          weight: .semibold,
          color: isSelected ? theme.onBrandAction : theme.brandActionBackground
        )

        Text(title)
          .font(.system(size: 15, weight: .medium))
      }
      .foregroundStyle(isSelected ? theme.onBrandAction : theme.onDarkFill)
      .padding(.horizontal, 14)
      .frame(height: 36)
      .background(isSelected ? theme.brandActionBackground : theme.brandCardSurface)
      .clipShape(Capsule())
      .overlay {
        Capsule()
          .stroke(isSelected ? theme.brandActionBackground : theme.brandControlBorder, lineWidth: flatHairline)
      }
    }
    .buttonStyle(.plain)
  }
}

#if os(iOS)
#Preview {
  SubjectChip(subject: SubjectOption(title: "test", systemImage: "test"),
              title: "test", isSelected: true, action: {})
}
#endif
