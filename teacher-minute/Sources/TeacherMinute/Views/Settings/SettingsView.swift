//
//  SettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

import SwiftUI

struct SettingsView: View {
    @State var viewModel: any SettingsViewModeling
    @Environment(\.appRouter) var router
    @Environment(\.openURL) var openURL
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    init(role: AppUserMode, viewModel: (any SettingsViewModeling)?) {
        if let viewModel {
            self._viewModel = State(wrappedValue: viewModel)
        } else {
            self._viewModel = State(wrappedValue: SettingsViewModel(role: role))
        }
    }

    var body: some View {
        NavigationStack(path: navigationPath) {
            ZStack {
                List {
                    ForEach(viewModel.sections) { section in
                        SettingsSectionView(section: section) { row in
                            viewModel.select(row)
                        }
                    }

                    Section {
                        Text(viewModel.appVersion)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.secondaryText)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(theme.screenBackground)

                loadingOverlay
            }
            .navigationTitle(viewModel.settingsTitle)
            .navigationDestination(for: SettingsDestination.self) { destination in
                destinationView(destination)
                    .navigationTitle(destination.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .appDialog(
            viewModel.activeConfirmation?.title ?? viewModel.settingsTitle,
            isPresented: isShowingConfirmation,
            message: viewModel.activeConfirmation?.message ?? "",
            actions: confirmationDialogActions
        )
        .appDialog(
            viewModel.alertTitle,
            isPresented: isShowingAlert,
            message: viewModel.alertMessage ?? "",
            actions: [AppDialogAction(viewModel.okLabel)]
        )
        .alert(viewModel.deleteAccountTitle, isPresented: isShowingReauthPasswordPrompt) {
            SecureField(viewModel.passwordPlaceholder, text: reauthPassword)
            Button(viewModel.cancelLabel, role: .cancel) {
                viewModel.reauthPassword = ""
            }
            Button(viewModel.deleteLabel, role: .destructive) {
                let password = viewModel.reauthPassword
                viewModel.reauthPassword = ""
                Task {
                    if await viewModel.completeAccountDeletion(withPassword: password) {
                        router.signOut()
                    }
                }
            }
        } message: {
            Text(viewModel.reauthPasswordMessage)
        }
        .sheet(item: contactSupportPreview) { request in
            ContactSupportPreviewSheet(
                viewModel: viewModel,
                request: request,
                isSubmitting: viewModel.isSubmittingContactSupport,
                onCancel: { viewModel.cancelContactSupportPreview() },
                onSubmit: { viewModel.submitContactSupport() }
            )
        }
        .onChange(of: viewModel.externalURL) { _, url in
            guard let url else { return }
            openURL(url)
            viewModel.consumeExternalURL()
        }
    }

    @ViewBuilder
    func destinationView(_ destination: SettingsDestination) -> some View {
        switch destination {
        case .accountSecurity:
            AccountSecuritySettingsView(viewModel: viewModel)
        case .appPreferences:
            AppPreferencesSettingsView(viewModel: viewModel)
        case .language:
            LanguageSettingsView(viewModel: viewModel)
        case .about:
            AboutSettingsView(viewModel: viewModel)
        case .contactUs:
            ContactSupportView(viewModel: viewModel)
        case .webPage(let title, let url):
            AboutWebView(url: url, title: title)
        case .studentPayments:
            StudentPaymentHistoryView(viewModel: viewModel)
        case .teacherPayouts:
            TeacherPayoutSettingsView()
        case .changePassword:
            ChangePasswordSettingsView(viewModel: viewModel)
        case .notifications:
            NotificationPreferencesSettingsView(viewModel: viewModel)
        case .privacyControls:
            PrivacyControlsSettingsView(viewModel: viewModel)
        }
    }

    @ViewBuilder
    var loadingOverlay: some View {
        if viewModel.isLoading {
            theme.scrim.opacity(0.18).ignoresSafeArea()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
                .tint(theme.primaryText)
        }
    }

    /// Cancel first so it reads as the safe default, then the confirm action —
    /// destructive confirmations get the danger styling.
    var confirmationDialogActions: [AppDialogAction] {
        var actions = [
            AppDialogAction(viewModel.cancelLabel, kind: .cancel) {
                viewModel.activeConfirmation = nil
            }
        ]
        if let confirmation = viewModel.activeConfirmation {
            actions.append(
                AppDialogAction(
                    confirmation.confirmTitle,
                    kind: confirmation.isDestructive ? .destructive : .primary
                ) {
                    confirm(confirmation)
                }
            )
        }
        return actions
    }

    // The view model is held as an existential, so the bindings SwiftUI needs
    // are built by hand instead of through `$viewModel`.
    var navigationPath: Binding<[SettingsDestination]> {
        Binding {
            viewModel.navigationPath
        } set: { path in
            viewModel.navigationPath = path
        }
    }

    var reauthPassword: Binding<String> {
        Binding {
            viewModel.reauthPassword
        } set: { password in
            viewModel.reauthPassword = password
        }
    }

    var contactSupportPreview: Binding<ContactSupportRequest?> {
        Binding {
            viewModel.contactSupportPreview
        } set: { request in
            viewModel.contactSupportPreview = request
        }
    }

    var isShowingAlert: Binding<Bool> {
        Binding {
            viewModel.showAlert
        } set: { isPresented in
            viewModel.showAlert = isPresented
        }
    }

    var isShowingReauthPasswordPrompt: Binding<Bool> {
        Binding {
            viewModel.showReauthPasswordPrompt
        } set: { isPresented in
            viewModel.showReauthPasswordPrompt = isPresented
        }
    }

    var isShowingConfirmation: Binding<Bool> {
        Binding {
            viewModel.activeConfirmation != nil
        } set: { isPresented in
            if !isPresented {
                viewModel.activeConfirmation = nil
            }
        }
    }

    private func confirm(_ confirmation: SettingsConfirmation) {
        viewModel.activeConfirmation = nil

        Task {
            if await viewModel.confirm(confirmation) {
                router.signOut()
            }
        }
    }
}

#if os(iOS)
#Preview ("teacher"){
  SettingsView(role: .teacher, viewModel: MockSettingsViewModel(role: .teacher))
  
}
#Preview ("student"){
  SettingsView(role: .student, viewModel: MockSettingsViewModel(role: .student))
}
#endif
