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
    let action: @Sendable () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)

                if let systemImage {
                    PlatformIcon(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(theme.authPink.opacity(isEnabled ? 1 : 0.55))
            .clipShape(Capsule())
            .shadow(color: theme.authPink.opacity(0.25), radius: 18, x: 0, y: 10)
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
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(theme.authPinkSoft)
            .frame(width: 54, height: 54)
            .overlay {
                PlatformIcon(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(theme.authPink)
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
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.authPrimaryText)

            HStack(spacing: 12) {
                PlatformIcon(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.authIcon)

                TextField(placeholder, text: $text)
                    .font(.system(size: 15))
                    .foregroundStyle(theme.authPrimaryText)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tint(theme.authPink)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(theme.authFieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(theme.authFieldBorder, lineWidth: 1)
            }
        }
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
        .background(theme.authFieldBorder.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func roleButton(for role: AuthRole) -> some View {
        let isSelected = selectedRole == role

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedRole = role
            }
        } label: {
            Text(role.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? theme.authPrimaryText : theme.authSecondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background {
                    AuthSelectedRoleBackground(
                        isSelected: isSelected,
                        shadowColor: theme.appPrimaryText
                    )
                }
        }
        .buttonStyle(.plain)
    }
}

struct AuthSelectedRoleBackground: View {
    let isSelected: Bool
    let shadowColor: Color

    var body: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white)
                .shadow(color: shadowColor.opacity(0.06), radius: 6, x: 0, y: 2)
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
                PlatformIcon(systemName: subject.systemImage)
                    .font(.system(size: 12, weight: .semibold))

                Text(subject.title)
                    .font(.system(size: 13, weight: .medium))
            }
			.foregroundStyle(theme.authPrimaryText)
            .padding(.horizontal, 14)
            .frame(height: 34)
			.background(isSelected ? theme.authPink : theme.authPinkSoft)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? theme.authPink : theme.authFieldBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
#if os(iOS)
struct SubjectChipScreens_Previews: PreviewProvider {
  static var previews: some View {
	SubjectChip(subject: SubjectOption(title: "test", systemImage: "test"), isSelected: true, action: {})
  }
}
#endif
