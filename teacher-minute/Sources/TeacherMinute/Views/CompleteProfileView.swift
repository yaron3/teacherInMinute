//
//  CompleteProfileView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct CompleteProfileView: View {
    @State var viewModel: CompleteProfileViewModel
    @Environment(\.appRouter) var router
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    init(viewModel: CompleteProfileViewModel = CompleteProfileViewModel(role: .student)) {
        self._viewModel = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                Text(LocalizationSupport.localized("Tell us a bit about yourself to get started with\nTeacher in a Minute."))
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .lineSpacing(5)
                    .padding(.top, 10)

                AuthInputField(
                    title: LocalizationSupport.localized("Full Name"),
                    placeholder: LocalizationSupport.localized("place holder name"),
                    systemImage: "person",
                    text: $viewModel.fullName,
                    textContentType: .name,
                    autocapitalization: .words
                )
                .padding(.top, 28)

                AuthInputField(
                    title: viewModel.role == .student
                    ? LocalizationSupport.localized("Phone Number (Optional)")
                    : LocalizationSupport.localized("Phone Number"),
                    placeholder: LocalizationSupport.localized("place holder phone number"),
                    systemImage: "phone",
                    text: $viewModel.phoneNumber,
                    keyboardType: .phonePad,
                    textContentType: .telephoneNumber
                )
                .padding(.top, 20)

                if viewModel.role == .student {
//                    gradePicker
//                        .padding(.top, 20)
                } else {
                    AuthInputField(
                        title: LocalizationSupport.localized("PayPal Email"),
                        placeholder: LocalizationSupport.localized("Optional"),
                        systemImage: "p.circle.fill",
                        text: $viewModel.paypalEmail,
                        keyboardType: .emailAddress,
                        textContentType: .emailAddress
                    )
                    .padding(.top, 20)
                }

                Spacer()

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                        .padding(.bottom, 8)
                }

                AuthPrimaryButton(
                    title: LocalizationSupport.localized("Continue"),
                    systemImage: "arrow.right",
                    isEnabled: viewModel.canContinue
                ) {
                    viewModel.continueFlow()
                }
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 18)
            .background(theme.screenBackground)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .onAppear {
                viewModel.onContinue = {
                    PermissionsSetupStore.markCompletedForCurrentUser()
                    router.enterMainTabs(role: viewModel.role)
                }
                viewModel.checkAndAutoAdvance()
            }
            .navigationTitle(LocalizationSupport.localized("Complete your profile"))
            .overlay {
                if viewModel.isCheckingCompletion {
                    ZStack {
                        theme.scrim.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().progressViewStyle(.circular).scaleEffect(1.6).tint(theme.primaryText)
                            Text(LocalizationSupport.localized("Loading your profile…"))
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.primaryText)
                        }
                    }
                }
            }
            .appDialog(
                LocalizationSupport.localized("Payout Details Missing"),
                isPresented: $viewModel.showMissingPayoutInfoConfirmation,
                message: LocalizationSupport.localized("You will not receive money until you provide bank account details or PayPal info."),
                actions: [
                    AppDialogAction(LocalizationSupport.localized("Add Now"), kind: .cancel),
                    AppDialogAction(LocalizationSupport.localized("Continue Anyway")) {
                        viewModel.continueWithoutPayoutInfo()
                    }
                ]
            )
        }
    }

    var gradePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizationSupport.localized("Your Grade"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            Menu {
                ForEach(viewModel.grades, id: \.self) { grade in
                    Button(grade) {
                        viewModel.grade = grade
                    }
                }
            } label: {
                HStack {
                    Text(viewModel.grade.isEmpty ? LocalizationSupport.localized("Select") : viewModel.grade)
                        .font(.system(size: 15))
                        .foregroundStyle(viewModel.grade.isEmpty ? theme.secondaryText : theme.primaryText)

                    Spacer()

                    PlatformIcon(
                        systemName: "chevron.down",
                        size: 12,
                        weight: .semibold,
                        color: theme.secondaryText
                    )
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                .background(theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
                        .stroke(theme.controlBorder, lineWidth: 1)
                }
            }
        }
    }
}
