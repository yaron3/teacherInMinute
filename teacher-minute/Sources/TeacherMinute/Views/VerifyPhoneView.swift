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
                .fill(theme.authPinkSoft)
                .frame(width: 76, height: 76)
                .shadow(color: theme.authPink.opacity(0.12), radius: 24, x: 0, y: 12)
                .overlay {
                    PlatformIcon(
                        systemName: "shield.lefthalf.filled",
                        size: 30,
                        weight: .semibold,
                        color: theme.authPink
                    )
                }

            Text("Verify your number")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.authPrimaryText)
                .padding(.top, 26)

            Text("We've sent a 4-digit security code to")
                .font(.system(size: 14))
                .foregroundStyle(theme.authSecondaryText)
                .padding(.top, 10)

            Text(viewModel.phoneNumber)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.authPrimaryText)
                .padding(.top, 6)

            Button {
                viewModel.changeContactInfo()
            } label: {
                HStack(spacing: 5) {
                    PlatformIcon(
                        systemName: "pencil",
                        size: 10,
                        weight: .semibold,
                        color: theme.authPink
                    )

                    Text("Change contact info")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(theme.authPink)
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
                        color: theme.authPink
                    )

                    Text("Resend Code Now")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(theme.authPink)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background(theme.authPinkSoft)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 36)

            Spacer()

            Rectangle()
                .fill(theme.authFieldBorder)
                .frame(height: 1)
                .padding(.horizontal, 18)

            HStack(spacing: 4) {
                Text("Having trouble?")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.authSecondaryText)

                Button {
                    viewModel.contactSupport()
                } label: {
                    Text("Contact Support")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.authPrimaryText)
                        .underline()
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 26)
            .padding(.bottom, 42)
        }
        .padding(.horizontal, 18)
        .background(Color(.systemBackground))
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
        .foregroundStyle(theme.authPrimaryText)
        .focused($focusedIndex, equals: index)
        .frame(width: 52, height: 56)
        .background(theme.appCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(theme.authFieldBorder, lineWidth: 1.5)
        }
    }
}
