//
//  SettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

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

struct AccountSecuritySettingsView: View {
    let viewModel: any SettingsViewModeling
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
    let viewModel: any SettingsViewModeling
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

    // These read through the localization service rather than the view model so
    // the rows re-render against the Remote Config template that lands when the
    // user switches language from this very screen.
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
    let viewModel: any SettingsViewModeling
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
    let viewModel: any SettingsViewModeling

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
                Text(viewModel.contactSupportIntroText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text(viewModel.contactSupportTitleSectionTitle)) {
                TextField(viewModel.contactSupportTitlePlaceholder, text: titleBinding)
                    .textInputAutocapitalization(.sentences)
                Text(viewModel.contactSupportTitleCounterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Section(header: Text(viewModel.contactSupportDescriptionSectionTitle)) {
                TextEditor(text: descriptionBinding)
                    .frame(minHeight: 160)
                Text(viewModel.contactSupportDescriptionCounterText)
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
                        Text(viewModel.contactSupportSubmitLabel)
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
    let viewModel: any SettingsViewModeling
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
                    Text(viewModel.contactSupportPreviewSectionTitle)
                }
            }
            .navigationTitle(viewModel.previewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.cancelLabel) {
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
                            Text(viewModel.sendLabel)
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
    let viewModel: any SettingsViewModeling
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
                    Text(viewModel.noPaymentsTitle)
                        .font(.headline)
                    Text(viewModel.noPaymentsSubtitle)
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
            let purchases = try await HistoryModel.shared.fetchPurchases(for: uid)
            monthSections = Self.groupByMonth(purchases, currencyCode: currencyCode)
        } catch {
            logger.error("[PaymentHistory] failed loading: \(error.localizedDescription)")
        }
    }

    /// Files each purchase under the month it was paid for. This used to group
    /// lessons by when they were taught, which answered a different question:
    /// a student who bought a package in March and used it through May saw the
    /// money spread across three months, and never saw the payment itself.
    private static func groupByMonth(_ purchases: [HistoryPurchase], currencyCode: String) -> [PaymentHistoryMonthSection] {
        let calendar = Calendar.current
        let monthFormatter = DateFormatter()
        monthFormatter.dateFormat = "MMMM yyyy"
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "MMM d, HH:mm"

        var purchasesByKey: [String: [HistoryPurchase]] = [:]
        var monthTitleByKey: [String: String] = [:]

        for purchase in purchases {
            let comps = calendar.dateComponents([.year, .month], from: purchase.purchasedAt)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            var existing = purchasesByKey[key] ?? []
            existing.append(purchase)
            purchasesByKey[key] = existing
            if monthTitleByKey[key] == nil {
                monthTitleByKey[key] = monthFormatter.string(from: purchase.purchasedAt)
            }
        }

        return purchasesByKey.keys
            .sorted(by: >)
            .compactMap { key in
                guard let monthPurchases = purchasesByKey[key], let title = monthTitleByKey[key] else { return nil }
                let sorted = monthPurchases.sorted { $0.purchasedAt > $1.purchasedAt }
                let totalCents = sorted.reduce(0) { $0 + $1.amountCents }
                let monthCurrencyCode = sorted.first?.currencyCode ?? currencyCode
                let entries = sorted.map { purchase in
                    PaymentHistoryEntry(
                        id: purchase.id,
                        title: purchase.title,
                        dateText: dayFormatter.string(from: purchase.purchasedAt),
                        amountText: LessonFormatting.currencyText(cents: purchase.amountCents, currencyCode: purchase.currencyCode)
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

/// Settings' entry point to the same payout editor Earnings uses — the
/// `TeacherPayoutMethodSheet` component itself, driven by the same
/// `TeacherEarningsViewModel`, so the two entry points can never drift into
/// showing different fields or writing to different places. The predecessor
/// of this view wrote a typed address straight to a `paypalEmail` field on
/// the profile, bypassing the domain check and the payout-method type system
/// entirely — a second, unvalidated path to the same real-world data.
///
/// Earnings presents this component as a sheet over the earnings history;
/// here, editing the payout method is the whole point of the screen, so it is
/// the pushed destination's entire body and "Cancel"/a successful save both
/// pop back to Settings instead of dismissing a sheet.
struct TeacherPayoutSettingsView: View {
    @State var payoutViewModel = TeacherEarningsViewModel()
    @Environment(\.dismiss) var dismiss

    var body: some View {
        TeacherPayoutMethodSheet(
            method: $payoutViewModel.payoutMethodDraft,
            availableTypes: payoutViewModel.availablePayoutMethodTypes,
            banks: payoutViewModel.banks,
            isSaving: payoutViewModel.isSavingPayoutMethod,
            errorMessage: payoutViewModel.payoutMethodErrorMessage,
            profilePhone: payoutViewModel.profilePhone,
            isConnectingPayPal: payoutViewModel.isConnectingPayPal,
            onUseProfilePhone: { payoutViewModel.useProfilePhone() },
            onConnectPayPal: { Task { await payoutViewModel.connectPayPalPayoutAccount() } },
            onSave: { Task { await payoutViewModel.savePayoutMethod() } },
            onCancel: { dismiss() }
        )
        .task {
            await payoutViewModel.loadForPayoutMethodEditing()
        }
        // Mirrors what a successful save/connect does in Earnings — there it
        // dismisses the sheet; here it pops back to Settings. Cancel already
        // pops directly above, so this only ever fires on that success path.
        .onChange(of: payoutViewModel.isEditingPayoutMethod) { _, isEditing in
            if !isEditing {
                dismiss()
            }
        }
    }
}

struct ChangePasswordSettingsView: View {
    let viewModel: any SettingsViewModeling

    var body: some View {
        Form {
            Section {
                Text(viewModel.changePasswordIntroText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(viewModel.sendResetEmailLabel) {
                    viewModel.sendPasswordReset()
                }
            }
        }
    }
}

struct NotificationPreferencesSettingsView: View {
    let viewModel: any SettingsViewModeling
    @AppStorage("notifyIncomingTeacherMessage") var notifyIncomingTeacherMessage = true
    @AppStorage("notifyGeneralAnnouncements") var notifyGeneralAnnouncements = true
    @State var notificationState: PermissionState = .notDetermined
    @State var isRequesting = false

    var body: some View {
        Form {
            Section(header: Text(viewModel.systemPermissionSectionTitle)) {
                HStack {
                    Text(viewModel.pushNotificationsLabel)
                    Spacer()
                    Text(notificationState.subtitle)
                        .foregroundStyle(.secondary)
                }
                actionButton
            }

            Section(header: Text(viewModel.notificationsSectionTitle)) {
                Toggle(viewModel.incomingMessageNotificationLabel, isOn: $notifyIncomingTeacherMessage)
                    .disabled(!notificationState.isGranted)
                Toggle(viewModel.generalAnnouncementsNotificationLabel, isOn: $notifyGeneralAnnouncements)
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
                    Text(viewModel.enableNotificationsLabel)
                    Spacer()
                    if isRequesting {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(isRequesting)
        case .denied:
            Button(viewModel.openSystemSettingsLabel) {
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

struct AppPreferencesSettingsView: View {
    let viewModel: any SettingsViewModeling
    @AppStorage(SessionPreferences.defaultQuestionTypeKey) var defaultQuestionType = ConversationType.audio.rawValue
    @AppStorage("appearanceMode") var appearanceMode = "system"

    var body: some View {
        Form {
            if viewModel.role == .student {
                Section(
                    header: Text(viewModel.defaultSessionTypeSectionTitle),
                    footer: Text(viewModel.defaultSessionTypeFooterText)
                ) {
                    MultilineConversationTypePicker(selection: $defaultQuestionType)
                }
            }

            Section(
                header: Text(viewModel.currencySectionTitle),
                footer: Text(viewModel.currencyFooterText)
            ) {
                HStack {
                    Text(viewModel.currencySectionTitle)
                    Spacer()
                    Text(viewModel.currencyValueLabel)
                        .foregroundStyle(.secondary)
                }
            }

            Section(header: Text(viewModel.appearanceSectionTitle)) {
                Picker(viewModel.appearanceSectionTitle, selection: $appearanceMode) {
                    Text(viewModel.appearanceSystemLabel).tag("system")
                    Text(viewModel.appearanceLightLabel).tag("light")
                    Text(viewModel.appearanceDarkLabel).tag("dark")
                }
                .pickerStyle(.segmented)
            }
        }
    }
}

 struct MultilineConversationTypePicker: View {
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(ConversationType.allCases, id: \.rawValue) { type in
                Button {
                    selection = type.rawValue
                } label: {
                    Text(type.displayName)
                        .font(.system(size: 15, weight: isSelected(type) ? .semibold : .regular))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .padding(.horizontal, 6)
                        .background {
                            if isSelected(type) {
                                Capsule()
                                    .fill(.background)
                                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
               // .accessibilityLabel(type.displayName)
                .accessibilitySelected(isSelected(type))
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.08), in: Capsule())
    }

    private func isSelected(_ type: ConversationType) -> Bool {
        selection == type.rawValue
    }
}

extension View {
    /// Marks a control as selected for assistive technology.
    ///
    /// The trait is only ever *added*: never hand `accessibilityAddTraits` an
    /// empty `AccessibilityTraits` (`[]`, or `AccessibilityTraits()`). On
    /// Android, SkipFuseUI declares `init() { self = [] }`, and `[]` routes
    /// through `SetAlgebra`'s default array-literal init straight back into
    /// `init()` — the recursion overflows the stack and kills the process
    /// before the screen ever draws. iOS is unaffected, so the crash only
    /// shows up on device.
    @ViewBuilder
    func accessibilitySelected(_ isSelected: Bool) -> some View {
        if isSelected {
            self.accessibilityAddTraits(.isSelected)
        } else {
            self
        }
    }
}

struct PrivacyControlsSettingsView: View {
    let viewModel: any SettingsViewModeling
    @AppStorage("showProfileImage") var showProfileImage = true
    @AppStorage("allowTeacherMessagesOutsideCalls") var allowTeacherMessagesOutsideCalls = true

    private let authService = AuthService()

    var body: some View {
        Form {
            Section(
                header: Text(viewModel.privacySectionTitle),
                footer: Text(viewModel.privacyFooterText)
            ) {
                Toggle(viewModel.showProfileImageLabel, isOn: $showProfileImage)
                Toggle(viewModel.allowMessagesOutsideCallsLabel, isOn: $allowTeacherMessagesOutsideCalls)
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
#Preview ("teacher"){
  SettingsView(role: .teacher, viewModel: MockSettingsViewModel(role: .teacher))
  
}
#Preview ("student"){
  SettingsView(role: .student, viewModel: MockSettingsViewModel(role: .student))
}
#endif
