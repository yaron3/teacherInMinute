//
//  VerifyPhoneView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct VerifyPhoneView: View {
    @State var viewModel = VerifyPhoneViewModel()
    @FocusState var focusedIndex: Int?
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 78)

            Circle()
                .fill(theme.accentBackground)
                .frame(width: 76, height: 76)
                .overlay {
                    PlatformIcon(
                        systemName: "shield.lefthalf.filled",
                        size: 30,
                        weight: .semibold,
                        color: theme.accent
                    )
                }

            Text(LocalizationSupport.localized("Verify your number"))
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .padding(.top, 26)

            Text(LocalizationSupport.localized("We've sent a 4-digit security code to"))
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .padding(.top, 10)

            Text(viewModel.phoneNumber)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .padding(.top, 6)

            Button {
                viewModel.changeContactInfo()
            } label: {
                HStack(spacing: 5) {
                    PlatformIcon(
                        systemName: "pencil",
                        size: 10,
                        weight: .semibold,
                        color: theme.accent
                    )

                    Text(LocalizationSupport.localized("Change contact info"))
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)

            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { index in
                    codeBox(index: index)
                }
            }
            .padding(.top, 34)

            Button {
                viewModel.resendCode()
            } label: {
                HStack(spacing: 6) {
                    PlatformIcon(
                        systemName: "arrow.clockwise",
                        size: 12,
                        weight: .semibold,
                        color: theme.accent
                    )

                    Text(LocalizationSupport.localized("Resend Code Now"))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(theme.accentBackground)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 36)

            Spacer()

            Rectangle()
                .fill(theme.controlBorder)
                .frame(height: 1)
                .padding(.horizontal, 18)

            HStack(spacing: 4) {
                Text(LocalizationSupport.localized("Having trouble?"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText)

                Button {
                    viewModel.contactSupport()
                } label: {
                    Text(LocalizationSupport.localized("Contact Support"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.primaryText)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 26)
            .padding(.bottom, 42)
        }
        .padding(.horizontal, 18)
        .background(theme.screenBackground)
        .navigationBarTitleDisplayMode(.inline)
        .trackScreen(AnalyticsScreen.verifyPhone)
        .onAppear {
            focusedIndex = 0
        }
    }

    func codeBox(index: Int) -> some View {
        TextField("", text: Binding(
            get: { viewModel.digits[index] },
            set: { newValue in
                let filtered = newValue.filter(\.isNumber)
                viewModel.digits[index] = String(filtered.prefix(1))

                if !filtered.isEmpty, index < 3 {
                    focusedIndex = index + 1
                }
            }
        ))
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.primaryText)
        .focused($focusedIndex, equals: index)
        .frame(width: 52, height: 56)
        .background(theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
                .stroke(theme.controlBorder, lineWidth: 1.5)
        }
    }
}
