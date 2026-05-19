//
//  SettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct SettingsView: View {
    @State var viewModel: SettingsViewModel
    @State var activeDestination: SettingsDestination?
    @Environment(\.appRouter) var router
    @Environment(\.openURL) var openURL
  @Environment(\.colorScheme) var colorScheme
  var role: AppUserMode
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  init(role: AppUserMode,viewModel: SettingsViewModel?) {
	if let viewModel {
	  self._viewModel = State(wrappedValue: viewModel)
	} else {
	  self._viewModel = State(wrappedValue: SettingsViewModel(role:role))
	}
	self.role = role
  }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                settingsContent
                    .offset(x: activeDestination != nil ? -geometry.size.width : 0)

                if let destination = activeDestination {
                    destinationContainer(destination)
                        .transition(.move(edge: .trailing))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: activeDestination)
        }
        .background(Color(.systemBackground))
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

    var settingsContent: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)
                        .padding(.top, 24)

                    VStack(spacing: 28) {
                        ForEach(viewModel.sections) { section in
                            settingsSection(section)
                        }
                    }
                    .padding(.top, 28)

                    Text(viewModel.appVersion)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.appSecondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
            }

            loadingOverlay
        }
        .background(Color(.systemBackground))
    }

    func destinationContainer(_ destination: SettingsDestination) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    activeDestination = nil
                } label: {
                    HStack(spacing: 5) {
                        PlatformIcon(
                            systemName: "chevron.left",
                            size: 14,
                            weight: .semibold,
                            color: theme.appPink
                        )
                        Text("Settings")
                            .font(.system(size: 16))
                            .foregroundStyle(theme.appPink)
                    }
                }

                Spacer()
            }
            .overlay {
                Text(destination.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.appPrimaryText)
            }
            .padding(.horizontal, 16)
            .frame(height: 44)

            Divider()

            destinationView(destination)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemBackground))
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

    func settingsSection(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.appSecondaryText)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    if let destination = row.destination {
                        SettingsRowView(row: row) {
                            activeDestination = destination
                        }
                    } else {
                        SettingsRowView(row: row) {
                            viewModel.select(row)
                        }
                    }

                    if index < section.rows.count - 1 {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(theme.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: theme.appPrimaryText.opacity(0.035), radius: 18, x: 0, y: 10)
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
                router.popToRoot()
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
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    settingsSection(viewModel.accountSecuritySection)
                        .padding(.top, 24)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }

            if viewModel.isLoading {
                theme.appPrimaryText.opacity(0.18).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(theme.appPrimaryText)
            }
        }
        .background(Color(.systemBackground))
    }

    func settingsSection(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.appSecondaryText)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    SettingsRowView(row: row) {
                        viewModel.select(row)
                    }

                    if index < section.rows.count - 1 {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(theme.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: theme.appPrimaryText.opacity(0.035), radius: 18, x: 0, y: 10)
        }
    }
}

struct LanguageSettingsView: View {
    let viewModel: SettingsViewModel
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("LANGUAGE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(theme.appSecondaryText)
                    .padding(.leading, 4)
                    .padding(.top, 24)

                VStack(spacing: 0) {
                    ForEach(Array(SettingsLanguageChoice.allCases.enumerated()), id: \.element.id) { index, language in
                        Button {
                            viewModel.selectedLanguage = language
                        } label: {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(theme.appGrayBackground)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        PlatformIcon(
                                            systemName: "globe",
                                            size: 13,
                                            weight: .semibold,
                                            color: theme.appPrimaryText
                                        )
                                    }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(language.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(theme.appPrimaryText)

                                    if let subtitle = language.subtitle {
                                        Text(subtitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(theme.appSecondaryText)
                                    }
                                }

                                Spacer()

                                if viewModel.selectedLanguage == language {
                                    PlatformIcon(
                                        systemName: "checkmark",
                                        size: 14,
                                        weight: .bold,
                                        color: theme.appPink
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .frame(height: language.subtitle == nil ? 54 : 64)
                        }
                        .buttonStyle(.plain)

                        if index < SettingsLanguageChoice.allCases.count - 1 {
                            Divider()
                                .padding(.leading, 58)
                        }
                    }
                }
                .padding(.vertical, 8)
                .background(theme.appCardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: theme.appPrimaryText.opacity(0.035), radius: 18, x: 0, y: 10)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }
}

struct AboutSettingsView: View {
    let viewModel: SettingsViewModel
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                settingsSection(viewModel.aboutSection)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }

    func settingsSection(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(theme.appSecondaryText)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    SettingsRowView(row: row) {
                        viewModel.select(row)
                    }

                    if index < section.rows.count - 1 {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(theme.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: theme.appPrimaryText.opacity(0.035), radius: 18, x: 0, y: 10)
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
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

    var body: some View {
        VStack(spacing: 18) {
            RoundedInfoCard {
                VStack(alignment: .leading, spacing: 12) {
                    Circle()
                        .fill(theme.appPurpleSoft)
                        .frame(width: 44, height: 44)
                        .overlay {
                            PlatformIcon(
                                systemName: "creditcard.fill",
                                size: 18,
                                weight: .semibold,
                                color: theme.appPurple
                            )
                        }

                    Text(LocalizationSupport.localized("PayPal Checkout"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)

                    Text(LocalizationSupport.localized("Today we support PayPal only. Students do not need to save a payment method in the app; PayPal asks for the student credentials during each purchase."))
                        .font(.system(size: 13))
                        .foregroundStyle(theme.appSecondaryText)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct TeacherPayoutSettingsView: View {
    @Bindable var viewModel: SettingsViewModel
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            RoundedInfoCard {
                VStack(alignment: .leading, spacing: 14) {
                    Circle()
                        .fill(theme.appPurpleSoft)
                        .frame(width: 44, height: 44)
                        .overlay {
                            PlatformIcon(
                                systemName: "p.circle.fill",
                                size: 20,
                                weight: .semibold,
                                color: theme.appPurple
                            )
                        }

                    Text(LocalizationSupport.localized("PayPal Payouts"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)

                    Text(LocalizationSupport.localized("Teachers must add and keep a valid PayPal email in order to receive payouts. Payments cannot be sent until this information is valid."))
                        .font(.system(size: 13))
                        .foregroundStyle(theme.appSecondaryText)
                        .lineSpacing(4)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(LocalizationSupport.localized("PayPal Email"))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.appPrimaryText)

                        TextField(LocalizationSupport.localized("teacher@example.com"), text: $viewModel.teacherPayPalEmail)
                            .font(.system(size: 15))
                            .foregroundStyle(theme.appPrimaryText)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 14)
                            .frame(height: 48)
                            .background(theme.authFieldBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(theme.authFieldBorder, lineWidth: 1)
                            }
                    }

                    Button {
                        viewModel.saveTeacherPayoutSettings()
                    } label: {
                        HStack {
                            if viewModel.isSavingPayoutSettings {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(theme.appPrimaryText)
                            } else {
                                PlatformIcon(
                                    systemName: "checkmark.circle.fill",
                                    size: 14,
                                    weight: .semibold,
                                    color: theme.appPrimaryText
                                )
                            }

                            Text(viewModel.isSavingPayoutSettings ? LocalizationSupport.localized("Saving...") : LocalizationSupport.localized("Save PayPal Info"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(theme.appPrimaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(theme.appPink)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSavingPayoutSettings)
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            await viewModel.loadTeacherPayoutSettings()
        }
    }
}

struct ChangePasswordSettingsView: View {
    let viewModel: SettingsViewModel
    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

    var body: some View {
        VStack(spacing: 18) {
            RoundedInfoCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(LocalizationSupport.localized("Change Password"))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.appPrimaryText)
                    Text(LocalizationSupport.localized("Send a password reset email to the email address on this account."))
                        .font(.system(size: 13))
                        .foregroundStyle(theme.appSecondaryText)
                    Button { viewModel.sendPasswordReset() } label: {
                        Text(LocalizationSupport.localized("Send Reset Email"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.appPrimaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(theme.appPink)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            Spacer()
        }
        .background(Color(.systemBackground))
    }
}

struct NotificationPreferencesSettingsView: View {
    @AppStorage("notifyIncomingTeacherMessage") var notifyIncomingTeacherMessage = true
    @AppStorage("notifyGeneralAnnouncements") var notifyGeneralAnnouncements = true
    @AppStorage("appearanceMode") var appearanceMode = "system"
    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                Toggle(LocalizationSupport.localized("Notify me when a teacher sends an incoming message"), isOn: $notifyIncomingTeacherMessage)
                Toggle(LocalizationSupport.localized("Notify me about general announcements"), isOn: $notifyGeneralAnnouncements)
                Picker(LocalizationSupport.localized("Appearance"), selection: $appearanceMode) {
                    Text(LocalizationSupport.localized("System")).tag("system")
                    Text(LocalizationSupport.localized("Light")).tag("light")
                    Text(LocalizationSupport.localized("Dark")).tag("dark")
                }
                .pickerStyle(.segmented)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.appPrimaryText)
            .padding(18)
            .background(theme.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(18)
        }
        .background(Color(.systemBackground))
    }
}

struct PrivacyControlsSettingsView: View {
    @AppStorage("showProfileImage") var showProfileImage = true
    @AppStorage("allowTeacherMessagesOutsideCalls") var allowTeacherMessagesOutsideCalls = true
    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 12) {
                Toggle(LocalizationSupport.localized("Show my profile image"), isOn: $showProfileImage)
                Toggle(LocalizationSupport.localized("Allow incoming messages from a teacher while not in a call"), isOn: $allowTeacherMessagesOutsideCalls)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.appPrimaryText)
            .padding(18)
            .background(theme.appCardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(18)
        }
        .background(Color(.systemBackground))
    }
}

struct SettingsRowView: View {
    let row: SettingsRow
    let action: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        Button(action: action) {
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

                Spacer()

                PlatformIcon(
                    systemName: "chevron.right",
                    size: 12,
                    weight: .semibold,
                    color: theme.appSecondaryText
                )
            }
            .padding(.horizontal, 16)
            .frame(height: row.subtitle == nil ? 54 : 64)
        }
        .buttonStyle(.plain)
    }
}

#if os(iOS)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
	  SettingsView(role: .student, viewModel: MockSettingsViewModel(role: .student))
    }
}
#endif
