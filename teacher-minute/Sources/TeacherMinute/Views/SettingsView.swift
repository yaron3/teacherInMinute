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
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                destinationView(destination)
                    .navigationTitle(destination.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .alert(viewModel.activeConfirmation?.title ?? "Settings", isPresented: isShowingConfirmation) {
            Button("Cancel", role: .cancel) {
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
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
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

    var body: some View {
        Form {
            Section(header: Text(LocalizationSupport.localized("Language"))) {
                ForEach(SettingsLanguageChoice.allCases) { language in
                    Button {
                        viewModel.updateLanguage(language)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(language.title)
                                if let subtitle = language.subtitle {
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

    var body: some View {
        Form {
            Section(header: Text(LocalizationSupport.localized("Notifications"))) {
                Toggle(LocalizationSupport.localized("Notify me when a teacher sends an incoming message"), isOn: $notifyIncomingTeacherMessage)
                Toggle(LocalizationSupport.localized("Notify me about general announcements"), isOn: $notifyGeneralAnnouncements)
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
