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
    let action: () -> Void

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
            .background(Color.authPink.opacity(isEnabled ? 1 : 0.55))
            .clipShape(Capsule())
            .shadow(color: Color.authPink.opacity(0.25), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

struct AuthIconHeader: View {
    let systemImage: String
    var backgroundColor: Color = .authPinkSoft
    var iconColor: Color = .authPink

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(backgroundColor)
            .frame(width: 54, height: 54)
            .overlay {
                PlatformIcon(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(iconColor)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.authPrimaryText)

            HStack(spacing: 12) {
                PlatformIcon(systemName: systemImage)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.authIcon)

                TextField(placeholder, text: $text)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.authPrimaryText)
                    .keyboardType(keyboardType)
                    .textContentType(textContentType)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .tint(Color.authPink)
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.authFieldBackground)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(Color.authFieldBorder, lineWidth: 1)
            }
        }
    }
}

struct AuthSegmentedRolePicker: View {
    @Binding var selectedRole: AuthRole

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AuthRole.allCases) { role in
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selectedRole = role
                    }
                } label: {
                    Text(role.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selectedRole == role ? Color.authPrimaryText : Color.authSecondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background {
                            if selectedRole == role {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(.white)
                                    .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Color.authFieldBorder.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct SubjectChip: View {
    let subject: SubjectOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                PlatformIcon(systemName: subject.systemImage)
                    .font(.system(size: 12, weight: .semibold))

                Text(subject.title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(isSelected ? .white : Color.authPrimaryText)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(isSelected ? Color.authPink : .white)
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(isSelected ? Color.authPink : Color.authFieldBorder, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}
