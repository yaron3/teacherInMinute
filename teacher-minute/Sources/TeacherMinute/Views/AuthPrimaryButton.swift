//
//  AuthPrimaryButton.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct AuthPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isEnabled = true
    let action: @MainActor () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)

                if let systemImage {
				  PlatformIcon(systemName: systemImage, size: 20, weight: .bold , color: isEnabled ? theme.onAccentText : theme.secondaryText)
                }
            }
            .font(.system(size: 17, weight: .bold))
            // Disabled drops the accent fill for a pale card, which the
            // on-accent colour is not readable against.
            .foregroundStyle(isEnabled ? theme.onAccentText : theme.secondaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(isEnabled ? theme.accent : theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct AuthIconHeader: View {
    let systemImage: String
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
            .fill(theme.cardBackground)
            .frame(width: 56, height: 56)
            .overlay {
                PlatformIcon(systemName: systemImage, size: 26, weight: .semibold, color: theme.primaryText)
            }
    }
}

struct AuthInputField: View {
    let title: String
    let placeholder: String
    let systemImage: String
    @Binding var text: String

    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .never
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.layoutDirection) var layoutDirection
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var contentAlignment: HorizontalAlignment {
    layoutDirection == .rightToLeft ? .trailing : .leading
  }
  var textAlignment: TextAlignment {
    layoutDirection == .rightToLeft ? .trailing : .leading
  }
    var body: some View {
	  VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            HStack(spacing: 12) {
                if layoutDirection == .leftToRight {
                    fieldIcon
                    inputField
                } else {
                    inputField
                    fieldIcon
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
        }
    }

    var fieldIcon: some View {
        PlatformIcon(systemName: systemImage)
            .font(.system(size: 18))
            .foregroundStyle(theme.secondaryText)
    }

    var inputField: some View {
        TextField(placeholder, text: $text)
            .font(.system(size: 17))
            .foregroundStyle(theme.primaryText)
            .keyboardType(keyboardType)
            .textContentType(textContentType)
            .textInputAutocapitalization(autocapitalization)
            .autocorrectionDisabled()
            .multilineTextAlignment(textAlignment)
            .tint(theme.accent)
    }
}

struct AuthSegmentedRolePicker: View {
    @Binding var selectedRole: AuthRole
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(AuthRole.allCases) { role in
                roleButton(for: role)
            }
        }
        .padding(3)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
    }

    private func roleButton(for role: AuthRole) -> some View {
        let isSelected = selectedRole == role

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedRole = role
            }
        } label: {
            Text(role.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? theme.primaryText : theme.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    AuthSelectedRoleBackground(
                        isSelected: isSelected,
                        shadowColor: theme.primaryText
                    )
                }
        }
        .buttonStyle(.plain)
    }
}

struct AuthSelectedRoleBackground: View {
	@Environment(\.colorScheme) var colorScheme
	var theme: AppTheme {
	  AppTheme(colorScheme: colorScheme)
	}
    let isSelected: Bool
    let shadowColor: Color

    var body: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous)
                .fill(theme.accent)
        }
    }
}

struct SubjectChip: View {
    let subject: SubjectOption
    let isSelected: Bool
    let action: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                PlatformIcon(systemName: subject.systemImage, size: 14, weight: .semibold)

                Text(LocalizationSupport.localized(subject.title))
                    .font(.system(size: 15, weight: .medium))
            }
            // Selected chips fill with ink, so the label has to invert.
            .foregroundStyle(isSelected ? theme.onAccentText : theme.primaryText)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(isSelected ? theme.accent : theme.screenBackground)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? theme.accent : theme.separator, lineWidth: flatHairline)
            }
        }
        .buttonStyle(.plain)
    }
}
#if os(iOS)
#Preview {
  SubjectChip(subject: SubjectOption(title: "test", systemImage: "test"), isSelected: true, action: {})
}
#endif
