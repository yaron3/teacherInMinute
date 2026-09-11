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

                Text(viewModel.introText)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
                    .lineSpacing(5)
                    .padding(.top, 10)

                AuthInputField(
                    title: viewModel.fullNameFieldTitle,
                    placeholder: viewModel.fullNamePlaceholder,
                    systemImage: "person",
                    text: $viewModel.fullName,
                    textContentType: .name,
                    autocapitalization: .words
                )
                .padding(.top, 28)

                AuthInputField(
                    title: viewModel.phoneFieldTitle(isOptional: viewModel.role == .student),
                    placeholder: viewModel.phonePlaceholder,
                    systemImage: "phone",
                    text: $viewModel.phoneNumber,
                    keyboardType: .phonePad,
                    textContentType: .telephoneNumber,
                    isValid: !viewModel.showsPhoneError,
                    errorMessage: viewModel.phoneErrorMessage
                )
                .padding(.top, 20)

                if viewModel.role == .student {
//                    gradePicker
//                        .padding(.top, 20)
                } else {
                    payoutMethodSection
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
                    title: viewModel.continueLabel,
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
            .onboardingBackHandling(viewModel: viewModel)
            .onAppear {
                viewModel.onContinue = {
                    if viewModel.shouldShowPermissionsOnContinue && PermissionsSetupStore.shouldShowForCurrentUser() {
                        // Pushed, not replaced: the permissions step is part of
                        // the same walk-backwards flow, and replacing here wiped
                        // every earlier step out of the stack.
                        router.push(.permissionsSetup(role: viewModel.role))
                    } else {
                        router.enterMainTabs(role: viewModel.role)
                    }
                }
                viewModel.checkAndAutoAdvance()
            }
            .navigationTitle(viewModel.screenTitle)
            .overlay {
                if viewModel.isCheckingCompletion {
                    ZStack {
                        theme.scrim.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView().progressViewStyle(.circular).scaleEffect(1.6).tint(theme.primaryText)
                            Text(viewModel.loadingText)
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.primaryText)
                        }
                    }
                }
            }
            .appDialog(
                viewModel.payoutMissingDialogTitle,
                isPresented: $viewModel.showMissingPayoutInfoConfirmation,
                message: viewModel.payoutMissingDialogMessage,
                actions: [
                    AppDialogAction(viewModel.addNowLabel, kind: .cancel),
                    AppDialogAction(viewModel.continueAnywayLabel) {
                        viewModel.continueWithoutPayoutInfo()
                    }
                ]
            )
        }
    }

    /// Which destination the teacher would like — the choice only, with no
    /// account details: those are typed later into the payout form, which opens
    /// on whichever tab is picked here.
    var payoutMethodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.payoutMethodSectionTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)

            PayoutMethodTypePicker(
                types: viewModel.availablePayoutMethodTypes,
                selected: viewModel.payoutMethodType,
                onSelect: { type in viewModel.selectPayoutMethodType(type) }
            )

            Text(viewModel.payoutMethodSectionHint)
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText)
        }
    }

    var gradePicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(viewModel.gradeSectionTitle)
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
                    Text(viewModel.gradeSelectionLabel)
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
