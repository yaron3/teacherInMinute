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
            .navigationTitle(LocalizationSupport.localized("Settings"))
            .navigationDestination(for: SettingsDestination.self) { destination in
                destinationView(destination)
                    .navigationTitle(destination.title)
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .appDialog(
            viewModel.activeConfirmation?.title ?? LocalizationSupport.localized("Settings"),
            isPresented: isShowingConfirmation,
            message: viewModel.activeConfirmation?.message ?? "",
            actions: confirmationDialogActions
        )
        .appDialog(
            viewModel.alertTitle,
            isPresented: $viewModel.showAlert,
            message: viewModel.alertMessage ?? "",
            actions: [AppDialogAction(LocalizationSupport.localized("OK"))]
        )
        .alert(LocalizationSupport.localized("Delete Account"), isPresented: $viewModel.showReauthPasswordPrompt) {
            SecureField(LocalizationSupport.localized("Password"), text: $viewModel.reauthPassword)
            Button(LocalizationSupport.localized("Cancel"), role: .cancel) {
                viewModel.reauthPassword = ""
            }
            Button(LocalizationSupport.localized("Delete"), role: .destructive) {
                let password = viewModel.reauthPassword
                viewModel.reauthPassword = ""
                Task {
                    if await viewModel.completeAccountDeletion(withPassword: password) {
                        router.signOut()
                    }
                }
            }
        } message: {
            Text(LocalizationSupport.localized("Enter your password to confirm account deletion."))
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
        case .appPreferences:
            AppPreferencesSettingsView(role: role)
        case .language:
            LanguageSettingsView(viewModel: viewModel)
        case .about:
            AboutSettingsView(viewModel: viewModel)
        case .contactUs:
            ContactSupportView(viewModel: viewModel)
        case .webPage(let title, let url):
            AboutWebView(url: url, title: title)
        case .studentPayments:
            StudentPaymentHistoryView()
        case .teacherPayouts:
            TeacherPayoutSettingsView(viewModel: viewModel)
        case .changePassword:
            ChangePasswordSettingsView(viewModel: viewModel)
        case .notifications:
            NotificationPreferencesSettingsView(role: role)
        case .mediaPermissions:
            MediaPermissionsSettingsView()
        case .privacyControls:
            PrivacyControlsSettingsView()
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
            AppDialogAction(LocalizationSupport.localized("Cancel"), kind: .cancel) {
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
                theme.scrim.opacity(0.18).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(theme.primaryText)
            }
        }
    }
}

struct LanguageSettingsView: View {
    let viewModel: SettingsViewModel
    @State var localizationManager = LocalizationManager.shared
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var service: any LocalizationServiceProtocol {
        localizationManager.service
    }

    var body: some View {
        // Reading these triggers a re-render once the Remote Config refresh
        // following a language change has completed.
        let _ = localizationManager.languageCode
        let _ = localizationManager.dataFetched

        ZStack {
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
            .disabled(localizationManager.isLoading)

            if localizationManager.isLoading {
                theme.scrim.opacity(0.18).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(theme.primaryText)
            }
        }
    }

    private func localizedTitle(for language: SettingsLanguageChoice) -> String {
        switch language {
        case .system: service.localized("System Language")
        case .english: "English"
        case .hebrew: "עברית"
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
                .fill(theme.cardBackground)
                .frame(width: 58, height: 58)
                .overlay {
                    PlatformIcon(
                        systemName: "gearshape.fill",
                        size: 22,
                        weight: .semibold,
                        color: theme.secondaryText
                    )
                }

            Text(destination.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.primaryText)

            Text(destination.placeholderMessage)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct StudentPaymentHistoryView: View {
    @State  var monthSections: [PaymentHistoryMonthSection] = []
    @State  var isLoading = true
    private let authService = AuthService()

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if monthSections.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "creditcard")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(LocalizationSupport.localized("No payments yet"))
                        .font(.headline)
                    Text(LocalizationSupport.localized("Your lesson payments will appear here."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(monthSections) { section in
                        Section {
                            ForEach(section.entries) { entry in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.title)
                                            .font(.system(size: 14, weight: .medium))
                                            .lineLimit(1)
                                        Text(entry.dateText)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(entry.amountText)
                                        .font(.system(size: 14, weight: .semibold))
                                }
                            }
                        } header: {
                            HStack {
                                Text(section.title)
                                Spacer()
                                Text(section.totalText)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        defer { isLoading = false }
        guard let uid = authService.currentUserID else { return }
        do {
            let currencyCode = try await HistoryModel.shared.fetchPurchasedCurrencyCode(for: uid)
            let lessons = try await HistoryModel.shared.fetchRecentLessons(for: uid, limit: 200)
            monthSections = Self.groupByMonth(lessons, currencyCode: currencyCode)
        } catch {
            logger.error("[PaymentHistory] failed loading: \(error.localizedDescription)")
        }
    }

    private static func groupByMonth(_ lessons: [HistoryLesson], currencyCode: String) -> [PaymentHistoryMonthSection] {
        let calendar = Calendar.current
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "MMM d, HH:mm"

        var lessonsByKey: [String: [HistoryLesson]] = [:]
        var monthTitleByKey: [String: String] = [:]

        for lesson in lessons {
            let comps = calendar.dateComponents([.year, .month], from: lesson.acceptedAt)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            var existing = lessonsByKey[key] ?? []
            existing.append(lesson)
            lessonsByKey[key] = existing
            if monthTitleByKey[key] == nil {
                monthTitleByKey[key] = monthFormatter.string(from: lesson.acceptedAt)
            }
        }

        return lessonsByKey.keys
            .sorted(by: >)
            .compactMap { key in
                guard let monthLessons = lessonsByKey[key], let title = monthTitleByKey[key] else { return nil }
                let sorted = monthLessons.sorted { $0.acceptedAt > $1.acceptedAt }
                let totalCents = sorted.reduce(0) { $0 + $1.costCents }
                let monthCurrencyCode = sorted.first?.currencyCode ?? currencyCode
                let entries = sorted.map { lesson in
                    PaymentHistoryEntry(
                        id: lesson.id,
                        title: lesson.title,
                        dateText: dayFormatter.string(from: lesson.acceptedAt),
                        amountText: LessonFormatting.currencyText(cents: lesson.costCents, currencyCode: lesson.currencyCode)
                    )
                }
                return PaymentHistoryMonthSection(
                    id: key,
                    title: title,
                    totalText: LessonFormatting.currencyText(cents: totalCents, currencyCode: monthCurrencyCode),
                    entries: entries
                )
            }
    }
}

 struct PaymentHistoryMonthSection: Identifiable {
    let id: String
    let title: String
    let totalText: String
    let entries: [PaymentHistoryEntry]
}

 struct PaymentHistoryEntry: Identifiable {
    let id: String
    let title: String
    let dateText: String
    let amountText: String
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
    @State var notificationState: PermissionState = .notDetermined
    @State var isRequesting = false
	let role: AppUserMode

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
			  Toggle(LocalizationSupport.localized(role == .student ? "Notify me when a teacher sends an incoming message" :"Notify me when a student sends an incoming message"), isOn: $notifyIncomingTeacherMessage)
                    .disabled(!notificationState.isGranted)
                Toggle(LocalizationSupport.localized("Notify me about general announcements"), isOn: $notifyGeneralAnnouncements)
                    .disabled(!notificationState.isGranted)
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

struct MediaPermissionsSettingsView: View {
    @State var micState: PermissionState = .notDetermined
    @State var cameraState: PermissionState = .notDetermined
    @State var isRequestingMic = false
    @State var isRequestingCamera = false

    var body: some View {
        Form {
            Section(header: Text(LocalizationSupport.localized("System Permissions"))) {
                permissionRow(
                    title: LocalizationSupport.localized("Microphone"),
                    subtitle: LocalizationSupport.localized("Required for audio and video sessions"),
                    icon: "mic.fill",
                    state: micState,
                    isRequesting: isRequestingMic,
                    onEnable: { Task { await requestMic() } }
                )
                permissionRow(
                    title: LocalizationSupport.localized("Camera"),
                    subtitle: LocalizationSupport.localized("Required for video sessions and taking photos"),
                    icon: "camera.fill",
                    state: cameraState,
                    isRequesting: isRequestingCamera,
                    onEnable: { Task { await requestCamera() } }
                )
            }
        }
        .task {
            micState = PermissionService.shared.captureStatus(for: .microphone)
            cameraState = PermissionService.shared.captureStatus(for: .camera)
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        subtitle: String,
        icon: String,
        state: PermissionState,
        isRequesting: Bool,
        onEnable: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            switch state {
            case .notDetermined:
                Button {
                    onEnable()
                } label: {
                    if isRequesting {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Text(LocalizationSupport.localized("Enable"))
                    }
                }
                .disabled(isRequesting)
            case .denied:
                Button(LocalizationSupport.localized("Open Settings")) {
                    PermissionService.shared.openAppSettings()
                }
                .foregroundStyle(.red)
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
    }

    private func requestMic() async {
        isRequestingMic = true
        defer { isRequestingMic = false }
        micState = await PermissionService.shared.requestCapturePermission(for: .microphone)
    }

    private func requestCamera() async {
        isRequestingCamera = true
        defer { isRequestingCamera = false }
        cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
    }
}

struct AppPreferencesSettingsView: View {
    let role: AppUserMode
    @AppStorage(SessionPreferences.defaultQuestionTypeKey) var defaultQuestionType = ConversationType.audio.rawValue
    @AppStorage("appearanceMode") var appearanceMode = "system"

    var body: some View {
        Form {
            if role == .student {
                Section(
                    header: Text(LocalizationSupport.localized("Default Session Type")),
                    footer: Text(LocalizationSupport.localized("This session type is preselected when you ask a teacher a question. You can still change it for each question."))
                ) {
                    Picker(LocalizationSupport.localized("Default Session Type"), selection: $defaultQuestionType) {
                        ForEach(ConversationType.allCases, id: \.rawValue) { type in
                            Text(type.displayName).tag(type.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section(
                header: Text(LocalizationSupport.localized("Currency")),
                footer: Text(LocalizationSupport.localized("Your currency is set to Israeli Shekel (ILS) and cannot be changed for now."))
            ) {
                HStack {
                    Text(LocalizationSupport.localized("Currency"))
                    Spacer()
                    Text(LocalizationSupport.localized("ILS"))
                        .foregroundStyle(.secondary)
                }
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

    private let authService = AuthService()

    var body: some View {
        Form {
            Section(
                header: Text(LocalizationSupport.localized("Privacy")),
                footer: Text(LocalizationSupport.localized("When turned off, your profile photo won't be shared with the other participant during a session."))
            ) {
                Toggle(LocalizationSupport.localized("Show my profile image"), isOn: $showProfileImage)
                Toggle(LocalizationSupport.localized("Allow incoming messages from a teacher while not in a call"), isOn: $allowTeacherMessagesOutsideCalls)
            }
        }
        .task { await loadShowProfileImage() }
        .onChange(of: showProfileImage) { _, newValue in
            Task { await persistShowProfileImage(newValue) }
        }
    }

    // The "Show my profile image" preference must live on the user's profile so
    // the backend can decide whether to share the photo with the other
    // participant — a device-local @AppStorage value is invisible to it.
    private func loadShowProfileImage() async {
        guard let uid = authService.currentUserID,
              let data = try? await UserService.shared.fetchRaw(uid: uid),
              let stored = data["showProfileImage"] as? Bool else { return }
        showProfileImage = stored
    }

    private func persistShowProfileImage(_ newValue: Bool) async {
        guard let uid = authService.currentUserID else { return }
        try? await UserService.shared.updateShowProfileImage(uid: uid, enabled: newValue)
    }
}

struct SettingsSectionView: View {
    let section: SettingsSection
    let onSelect: (SettingsRow) -> Void
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

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
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.primaryText)
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
            FlatIconTile(
                systemName: row.systemImage,
                size: 40,
                tint: row.isDestructive ? theme.danger : theme.primaryText
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(row.isDestructive ? theme.danger : theme.primaryText)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

#if os(iOS)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
	  SettingsView(role: .student, viewModel: MockSettingsViewModel(role: .student))
    }
}
#endif
