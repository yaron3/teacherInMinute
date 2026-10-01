//
//  SettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct SettingsView: View {
    @State var viewModel: any SettingsViewModeling
    @Environment(\.openURL) var openURL

    init(role: AppUserMode, viewModel: (any SettingsViewModeling)?) {
        if let viewModel {
            self._viewModel = State(wrappedValue: viewModel)
        } else {
            self._viewModel = State(wrappedValue: SettingsViewModel(role: role))
        }
    }

    var body: some View {
        NavigationStack(path: navigationPath) {
            SettingsRootView(viewModel: viewModel)
                .navigationDestination(for: SettingsDestination.self) { destination in
                    destinationView(destination)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationBarBackButtonHidden(true)
                }
        }
        .appDialog(
            viewModel.alertTitle,
            isPresented: isShowingAlert,
            message: viewModel.alertMessage ?? "",
            actions: [AppDialogAction(viewModel.okLabel)]
        )
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
        .trackScreen(AnalyticsScreen.settings)
    }

    /// Each page draws its own header, with the way back.
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
            AboutWebView(url: url, title: title, backLabel: viewModel.backLabel)
        case .studentPayments:
            StudentPaymentHistoryView(viewModel: viewModel)
        case .teacherPayouts:
            TeacherPayoutSettingsView()
        case .notifications:
            NotificationPreferencesSettingsView(viewModel: viewModel)
        case .privacyControls:
            PrivacyControlsSettingsView(viewModel: viewModel)
        }
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
}

#if os(iOS)
#Preview ("teacher"){
  SettingsView(role: .teacher, viewModel: MockSettingsViewModel(role: .teacher))
}
#Preview ("student"){
  SettingsView(role: .student, viewModel: MockSettingsViewModel(role: .student))
}
#endif
