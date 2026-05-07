//
//  CreateAccountView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 05/05/2026.
//


import SwiftUI

struct CreateAccountView: View {
    @State var emailOrPhone = ""
    @State var password = ""
    @State var agreeTerms = true
    @State var sendUpdates = false
    @State var isPasswordVisible = false

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            VStack(spacing: 0) {
                //header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        titleSection
                        inputCard
                        checkboxSection
                        continueButton
                        dividerSection
                        socialButtons
                    }
                    .padding(.horizontal, 26)
                    .padding(.top, 18)
                }

                bottomLoginSection
            }
        }
    }

    var header: some View {
        HStack {
            Button {
                // Back action
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color(hex: "#111827"))
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 6)
                    )
            }

            Spacer()
        }
        .padding(.horizontal, 26)
        .padding(.top, 12)
    }

    var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Create Account")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Color(hex: "#111827"))

            Text("Join Math Connect to start learning or\nteaching today.")
                .font(.system(size: 16, weight: .regular))
                .lineSpacing(5)
                .foregroundStyle(Color(hex: "#6B7280"))
        }
    }

    var inputCard: some View {
        VStack(alignment: .leading, spacing: 22) {
            fieldSection(
                title: "Email or Phone",
                icon: "envelope",
                placeholder: "Enter your email or phone",
                text: $emailOrPhone,
                isSecure: false
            )

            fieldSection(
                title: "Password",
                icon: "lock.fill",
                placeholder: "Create a strong password",
                text: $password,
                isSecure: !isPasswordVisible,
                trailingIcon: isPasswordVisible ? "eye" : "eye.slash",
                trailingAction: {
                    isPasswordVisible.toggle()
                }
            )
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.045), radius: 18, x: 0, y: 10)
        )
    }

    func fieldSection(
        title: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool,
        trailingIcon: String? = nil,
        trailingAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#111827"))

            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color(hex: "#9CA3AF"))
                    .frame(width: 20)

                Group {
                    if isSecure {
                        SecureField(placeholder, text: text)
                    } else {
                        TextField(placeholder, text: text)
                            .keyboardType(title == "Email or Phone" ? .emailAddress : .default)
                            .textInputAutocapitalization(.never)
                    }
                }
                .font(.system(size: 16))
                .foregroundStyle(Color(hex: "#111827"))

                if let trailingIcon {
                    Button {
                        trailingAction?()
                    } label: {
                        Image(systemName: trailingIcon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color(hex: "#9CA3AF"))
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(hex: "#F9FAFB"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color(hex: "#EEF2F7"), lineWidth: 1)
                    )
            )
        }
    }

    var checkboxSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            checkboxRow(
                isOn: $agreeTerms,
                text: "",
                isTermsRow: true
            )

            checkboxRow(
                isOn: $sendUpdates,
                text: "Send me occasional updates and tips about\nMath Connect.",
                isTermsRow: false
            )
        }
        .padding(.horizontal, 8)
    }

    func checkboxRow(
        isOn: Binding<Bool>,
        text: String,
        isTermsRow: Bool = false
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                isOn.wrappedValue.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isOn.wrappedValue ? Color(hex: "#EC4899") : Color.white)
                        .frame(width: 18, height: 18)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(
                                    isOn.wrappedValue ? Color(hex: "#EC4899") : Color(hex: "#CBD5E1"),
                                    lineWidth: 1
                                )
                        )

                    if isOn.wrappedValue {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)

            if isTermsRow {
                termsTextView()
            } else {
                Text(text)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(Color(hex: "#6B7280"))
            }
        }
    }

    func termsTextView() -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 0) {
                Text("I agree to the ")
                    .foregroundStyle(Color(hex: "#6B7280"))

                Text("Terms of Service")
                    .foregroundStyle(Color(hex: "#EC4899"))

                Text(" and")
                    .foregroundStyle(Color(hex: "#6B7280"))
            }

            Text("Privacy Policy.")
                .foregroundStyle(Color(hex: "#EC4899"))
        }
        .font(.system(size: 14))
        .lineSpacing(4)
    }

    var continueButton: some View {
        Button {
            // Continue action
        } label: {
            Text("Continue to Role Selection")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule()
                        .fill(Color(hex: "#EC4899"))
                        .shadow(color: Color(hex: "#EC4899").opacity(0.28), radius: 14, x: 0, y: 8)
                )
        }
        .padding(.top, 4)
    }

    var dividerSection: some View {
        HStack(spacing: 16) {
            Rectangle()
                .fill(Color(hex: "#E5E7EB"))
                .frame(height: 1)

            Text("Or continue with")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: "#6B7280"))
                .lineLimit(1)

            Rectangle()
                .fill(Color(hex: "#E5E7EB"))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
    }

    var socialButtons: some View {
        HStack(spacing: 16) {
            socialButton(title: "Google", icon: "g.circle.fill")
            socialButton(title: "Apple", icon: "apple.logo")
        }
    }

    func socialButton(title: String, icon: String) -> some View {
        Button {
            // Social login action
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))

                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color(hex: "#111827"))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color(hex: "#E5E7EB"), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.025), radius: 6, x: 0, y: 4)
            )
        }
    }

    var bottomLoginSection: some View {
        HStack(spacing: 4) {
            Text("Already have an account?")
                .foregroundStyle(Color(hex: "#6B7280"))

            Button {
                // Login action
            } label: {
                Text("Log In")
                    .foregroundStyle(Color(hex: "#EC4899"))
            }
        }
        .font(.system(size: 14))
        .padding(.bottom, 18)
    }
}

#if os(iOS)
struct CreateAccountView_Previews: PreviewProvider {
    static var previews: some View {
        CreateAccountView()
    }
}
#endif
