//
//  ResetPasswordView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct ResetPasswordView: View {
    @State var viewModel = ResetPasswordViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AuthIconHeader(systemImage: "key.fill")
                .padding(.top, 42)

            Text("Reset Password")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Color.authPrimaryText)
                .padding(.top, 26)

            Text("Enter your email or phone number and we'll\nsend you instructions to reset your password.")
                .font(.system(size: 15))
                .foregroundStyle(Color.authSecondaryText)
                .lineSpacing(5)
                .padding(.top, 8)

            formCard
                .padding(.top, 34)

            AuthPrimaryButton(title: "Send Reset Link", isEnabled: viewModel.canSubmit) {
                viewModel.sendResetLink()
            }
            .padding(.top, 22)

            Spacer()

            Button {
                // NavigationStack back action should be handled by caller/environment if needed.
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))

                    Text("Back to Log In")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(Color.authSecondaryText)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 34)
        }
        .padding(.horizontal, 18)
        .background(Color(.systemBackground))
        .navigationBarTitleDisplayMode(.inline)
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
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.035), radius: 24, x: 0, y: 14)
    }

    var methodPicker: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation {
                    viewModel.method = .email
                }
            } label: {
                Text("Email")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.authPrimaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(viewModel.method == .email ? .white : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Button {
                withAnimation {
                    viewModel.method = .phone
                }
            } label: {
                Text("Phone")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.authSecondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(viewModel.method == .phone ? .white : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(3)
        .background(Color.authFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
    }
}