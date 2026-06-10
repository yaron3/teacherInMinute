//
//  SettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct SettingsView: View {
    @State var viewModel: SettingsViewModel
    @Environment(\.appRouter) var router
    @Environment(\.openURL) var openURL
    @Environment(\.colorScheme) var colorScheme
    var role: AppUserMode
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    init(role: AppUserMode, viewModel: SettingsViewModel?) {
        if let viewModel {
            self._viewModel = State(wrappedValue: viewModel)
        } else {
            self._viewModel = State(wrappedValue: SettingsViewModel(role: role))
        }
        self.role = role
    }

    var body: some View {
        NavigationStack(path: $viewModel.navigationPath) {
            ZStack {
                List {
                    ForEach(viewModel.sections) { section in
                        SettingsSectionView(section: section) { row in
                            viewModel.select(row)
                        }
                    }

                    Section {
                        Text(viewModel.appVersion)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.appSecondaryText)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }

                loadingOverlay
            }
            .navigationTitle(LocalizationSupport.localized("Settings"))
            .navigationDestination(for: SettingsDestination.self) { destination in
                destinationView(destination)
                    .navigationTitle(destination.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert(viewModel.activeConfirmation?.title ?? "Settings", isPresented: isShowingConfirmation) {
            Button(LocalizationSupport.localized("Cancel"), role: .cancel) {
                viewModel.activeConfirmation = nil
            }
            if let confirmation = viewModel.activeConfirmation {
                Button(confirmation.confirmTitle, role: confirmation.isDestructive ? .destructive : nil) {
                    confirm(confirmation)
                }
            }
        } message: {
            Text(viewModel.activeConfirmation?.message ?? "")
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button(LocalizationSupport.localized("OK"), role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .sheet(item: $viewModel.contactSupportPreview) { request in
            ContactSupportPreviewSheet(
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
        case .language:
            LanguageSettingsView(viewModel: viewModel)
        case .about:
            AboutSettingsView(viewModel: viewModel)
        case .contactUs:
            ContactSupportView(viewModel: viewModel)
        case .webPage(let title, let url):
            AboutWebView(url: url, title: title)
        case .studentPayments:
            StudentPaymentsSettingsView(viewModel: viewModel)
        case .teacherPayouts:
            TeacherPayoutSettingsView(viewModel: viewModel)
        case .changePassword:
            ChangePasswordSettingsView(viewModel: viewModel)
        case .notifications:
            NotificationPreferencesSettingsView()
        case .privacyControls:
            PrivacyControlsSettingsView()
        }
    }

    @ViewBuilder
    var loadingOverlay: some View {
        if viewModel.isLoading {
            theme.appPrimaryText.opacity(0.18).ignoresSafeArea()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
                .tint(theme.appPrimaryText)
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

struct AccountSecuritySettingsView: View {
    let viewModel: SettingsViewModel
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    var body: some View {
        ZStack {
            List {
                SettingsSectionView(section: viewModel.accountSecuritySection) { row in
                    viewModel.select(row)
                }
            }

            if viewModel.isLoading {
                theme.appPrimaryText.opacity(0.18).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(theme.appPrimaryText)
            }
        }
    }
}

struct LanguageSettingsView: View {
    let viewModel: SettingsViewModel
    @State var localizationManager = LocalizationManager.shared

    var service: any LocalizationServiceProtocol {
        localizationManager.service
    }

    var body: some View {
        // Reading these triggers a re-render once the Remote Config refresh
        // following a language change has completed.
        let _ = localizationManager.languageCode
        let _ = localizationManager.dataFetched

        Form {
            Section(header: Text(service.localized("Language"))) {
                ForEach(SettingsLanguageChoice.allCases) { language in
                    Button {
                        viewModel.updateLanguage(language)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(localizedTitle(for: language))
                                if let subtitle = localizedSubtitle(for: language) {
                                    Text(subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if viewModel.selectedLanguage == language {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
    }

    private func localizedTitle(for language: SettingsLanguageChoice) -> String {
        switch language {
        case .system: service.localized("System Language")
        case .english: service.localized("English")
        case .hebrew: service.localized("Hebrew")
        }
    }

    private func localizedSubtitle(for language: SettingsLanguageChoice) -> String? {
        switch language {
        case .system: service.localized("Use the device language")
        case .english, .hebrew: nil
        }
    }
}

struct AboutSettingsView: View {
    let viewModel: SettingsViewModel
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    var body: some View {
        List {
            SettingsSectionView(section: viewModel.aboutSection) { row in
                viewModel.select(row)
            }
        }
    }
}

struct ContactSupportView: View {
    @Bindable var viewModel: SettingsViewModel

    var titleBinding: Binding<String> {
        Binding {
            viewModel.contactSupportTitle
        } set: { value in
            viewModel.updateContactSupportTitle(value)
        }
    }

    var descriptionBinding: Binding<String> {
        Binding {
            viewModel.contactSupportDescription
        } set: { value in
            viewModel.updateContactSupportDescription(value)
        }
    }

    var body: some View {
        Form {
            Section {
                Text(LocalizationSupport.localized("Send a message to support. You will preview the data before it is sent."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text(LocalizationSupport.localized("Title"))) {
                TextField(LocalizationSupport.localized("What can we help with?"), text: titleBinding)
                    .textInputAutocapitalization(.sentences)
                Text("\(viewModel.contactSupportTitle.count)/\(viewModel.contactSupportTitleMaxLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Section(header: Text(LocalizationSupport.localized("Description"))) {
                TextEditor(text: descriptionBinding)
                    .frame(minHeight: 160)
                Text("\(viewModel.contactSupportDescription.count)/\(viewModel.contactSupportDescriptionMaxLength)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    viewModel.previewContactSupport()
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(LocalizationSupport.localized("Preview and Submit"))
                    }
                }
                .disabled(viewModel.isLoading || viewModel.isSubmittingContactSupport)
            }
        }
        .onAppear {
            viewModel.contactSupportAppeared()
        }
    }
}

struct ContactSupportPreviewSheet: View {
    let request: ContactSupportRequest
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(request.previewRows, id: \.0) { title, value in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(value)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(LocalizationSupport.localized("Data to be sent"))
                }
            }
            .navigationTitle(LocalizationSupport.localized("Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(LocalizationSupport.localized("Cancel")) {
                        onCancel()
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSubmit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(LocalizationSupport.localized("Send"))
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }
}

struct SettingsPlaceholderView: View {
    let destination: SettingsDestination
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(theme.appGrayBackground)
                .frame(width: 58, height: 58)
                .overlay {
                    PlatformIcon(
                        systemName: "gearshape.fill",
                        size: 22,
                        weight: .semibold,
                        color: theme.appSecondaryText
                    )
                }

            Text(destination.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.appPrimaryText)

            Text(destination.placeholderMessage)
                .font(.system(size: 13))
                .foregroundStyle(theme.appSecondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct StudentPaymentsSettingsView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section(header: Text(LocalizationSupport.localized("PayPal Checkout"))) {
                Text(LocalizationSupport.localized("Today we support PayPal only. Students do not need to save a payment method in the app; PayPal asks for the student credentials during each purchase."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TeacherPayoutSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Text(LocalizationSupport.localized("Teachers must add and keep a valid PayPal email in order to receive payouts. Payments cannot be sent until this information is valid."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text(LocalizationSupport.localized("PayPal Email"))) {
                TextField(LocalizationSupport.localized("teacher@example.com"), text: $viewModel.teacherPayPalEmail)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button {
                    viewModel.saveTeacherPayoutSettings()
                } label: {
                    HStack {
                        if viewModel.isSavingPayoutSettings {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.isSavingPayoutSettings ? LocalizationSupport.localized("Saving...") : LocalizationSupport.localized("Save PayPal Info"))
                    }
                }
                .disabled(viewModel.isSavingPayoutSettings)
            }
        }
        .task {
            await viewModel.loadTeacherPayoutSettings()
        }
    }
}

struct ChangePasswordSettingsView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        Form {
            Section {
                Text(LocalizationSupport.localized("Send a password reset email to the email address on this account."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(LocalizationSupport.localized("Send Reset Email")) {
                    viewModel.sendPasswordReset()
                }
            }
        }
    }
}

struct NotificationPreferencesSettingsView: View {
    @AppStorage("notifyIncomingTeacherMessage") var notifyIncomingTeacherMessage = true
    @AppStorage("notifyGeneralAnnouncements") var notifyGeneralAnnouncements = true
    @AppStorage("appearanceMode") var appearanceMode = "system"
    @State var notificationState: PermissionState = .notDetermined
    @State var isRequesting = false

    var body: some View {
        Form {
            Section(header: Text(LocalizationSupport.localized("System Permission"))) {
                HStack {
                    Text(LocalizationSupport.localized("Push Notifications"))
                    Spacer()
                    Text(notificationState.subtitle)
                        .foregroundStyle(.secondary)
                }
                actionButton
            }

            Section(header: Text(LocalizationSupport.localized("Notifications"))) {
                Toggle(LocalizationSupport.localized("Notify me when a teacher sends an incoming message"), isOn: $notifyIncomingTeacherMessage)
                    .disabled(!notificationState.isGranted)
                Toggle(LocalizationSupport.localized("Notify me about general announcements"), isOn: $notifyGeneralAnnouncements)
                    .disabled(!notificationState.isGranted)
            }

            Section(header: Text(LocalizationSupport.localized("Appearance"))) {
                Picker(LocalizationSupport.localized("Appearance"), selection: $appearanceMode) {
                    Text(LocalizationSupport.localized("System")).tag("system")
                    Text(LocalizationSupport.localized("Light")).tag("light")
                    Text(LocalizationSupport.localized("Dark")).tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
        .task {
            notificationState = await PermissionService.shared.notificationStatus()
            if notificationState == .notDetermined {
                await requestNotifications()
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch notificationState {
        case .notDetermined:
            Button {
                Task { await requestNotifications() }
            } label: {
                HStack {
                    Text(LocalizationSupport.localized("Enable Notifications"))
                    Spacer()
                    if isRequesting {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(isRequesting)
        case .denied:
            Button(LocalizationSupport.localized("Open System Settings")) {
                PermissionService.shared.openAppSettings()
            }
        case .granted:
            EmptyView()
        }
    }

    private func requestNotifications() async {
        isRequesting = true
        defer { isRequesting = false }
        let result = await PermissionService.shared.requestNotifications()
        notificationState = result
    }
}

struct PrivacyControlsSettingsView: View {
    @AppStorage("showProfileImage") var showProfileImage = true
    @AppStorage("allowTeacherMessagesOutsideCalls") var allowTeacherMessagesOutsideCalls = true

    var body: some View {
        Form {
            Section(header: Text(LocalizationSupport.localized("Privacy"))) {
                Toggle(LocalizationSupport.localized("Show my profile image"), isOn: $showProfileImage)
                Toggle(LocalizationSupport.localized("Allow incoming messages from a teacher while not in a call"), isOn: $allowTeacherMessagesOutsideCalls)
            }
        }
    }
}

struct SettingsSectionView: View {
    let section: SettingsSection
    let onSelect: (SettingsRow) -> Void

    var body: some View {
        Section {
            ForEach(section.rows) { row in
                if let destination = row.destination {
                    NavigationLink(value: destination) {
                        SettingsRowView(row: row)
                    }
                } else {
                    Button {
                        onSelect(row)
                    } label: {
                        SettingsRowView(row: row)
                    }
                }
            }
        } header: {
            Text(section.title)
        }
    }
}

struct SettingsRowView: View {
    let row: SettingsRow
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    var body: some View {
        HStack(spacing: 14) {
            Circle()
                .fill(theme.primaryBackground)
                .frame(width: 34, height: 34)
                .overlay {
                    PlatformIcon(
                        systemName: row.systemImage,
                        size: 13,
                        weight: .semibold,
                        color: theme.primaryText
                    )
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(row.isDestructive ? .red : theme.appPrimaryText)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.appSecondaryText)
                }
            }
        }
    }
}

#if os(iOS)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
	  SettingsView(role: .student, viewModel: MockSettingsViewModel(role: .student))
    }
}
#endif
