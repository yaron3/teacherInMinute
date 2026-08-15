//
//  ResetPasswordView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct ResetPasswordView: View {
    @State var viewModel = ResetPasswordViewModel()
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthIconHeader(systemImage: "key.fill")
                .padding(.top, 42)

            Text(LocalizationSupport.localized("Reset Password"))
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(theme.authPrimaryText)
                .padding(.top, 26)

            Text(LocalizationSupport.localized("Enter your email or phone number and we'll\nsend you instructions to reset your password."))
                .font(.system(size: 15))
                .foregroundStyle(theme.authSecondaryText)
                .lineSpacing(5)
                .padding(.top, 8)

            formCard
                .padding(.top, 34)

            AuthPrimaryButton(title: LocalizationSupport.localized("Send Reset Link"), isEnabled: viewModel.canSubmit) {
                viewModel.sendResetLink()
            }
            .padding(.top, 22)

            Spacer()

            Button {
                // NavigationStack back action should be handled by caller/environment if needed.
            } label: {
                HStack(spacing: 6) {
                    PlatformIcon(
                        systemName: "chevron.left",
                        size: 12,
                        weight: .semibold,
                        color: theme.authSecondaryText
                    )

                    Text(LocalizationSupport.localized("Back to Log In"))
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(theme.authSecondaryText)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 18)
        .background(theme.flatSurface)
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(AnalyticsScreen.resetPassword)
    }

    var formCard: some View {
        VStack(spacing: 24) {
            methodPicker

            if viewModel.method == .email {
                AuthInputField(
                    title: "Email Address",
                    placeholder: "Enter your email",
                    systemImage: "envelope",
                    text: $viewModel.email,
                    keyboardType: .emailAddress,
                    textContentType: .emailAddress
                )
            } else {
                AuthInputField(
                    title: "Phone Number",
                    placeholder: "Enter your phone",
                    systemImage: "phone",
                    text: $viewModel.phone,
                    keyboardType: .phonePad,
                    textContentType: .telephoneNumber
                )
            }
        }
        .padding(24)
        .background(theme.flatSurfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
    }

    var methodPicker: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation {
                    viewModel.method = .email
                }
            } label: {
                Text(LocalizationSupport.localized("Email"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.authPrimaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(viewModel.method == .email ?theme.flatSurfaceRaised: .clear)
                    .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
            }

            Button {
                withAnimation {
                    viewModel.method = .phone
                }
            } label: {
                Text(LocalizationSupport.localized("Phone"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.authSecondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(viewModel.method == .phone ?theme.flatSurfaceRaised: .clear)
                    .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
            }
        }
        .padding(3)
        .background(theme.authFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
    }
}
