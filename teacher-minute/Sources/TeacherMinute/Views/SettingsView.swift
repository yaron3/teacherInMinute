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

    init(viewModel: SettingsViewModel = SettingsViewModel()) {
        self._viewModel = State(wrappedValue: viewModel)
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
                        .foregroundStyle(Color.appPrimaryText)
                        .padding(.top, 24)

                    VStack(spacing: 28) {
                        ForEach(viewModel.sections) { section in
                            settingsSection(section)
                        }
                    }
                    .padding(.top, 28)

                    Text(viewModel.appVersion)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appSecondaryText)
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
                            color: Color.appPink
                        )
                        Text("Settings")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.appPink)
                    }
                }

                Spacer()
            }
            .overlay {
                Text(destination.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appPrimaryText)
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
        case .changePassword, .teacherPayouts, .studentPayments, .notifications, .privacyControls:
            SettingsPlaceholderView(destination: destination)
        }
    }

    func settingsSection(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.appSecondaryText)
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
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: 18, x: 0, y: 10)
        }
    }

    @ViewBuilder
    var loadingOverlay: some View {
        if viewModel.isLoading {
            Color.black.opacity(0.18).ignoresSafeArea()
            ProgressView()
                .progressViewStyle(.circular)
                .scaleEffect(1.4)
                .tint(.white)
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
                Color.black.opacity(0.18).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(.white)
            }
        }
        .background(Color(.systemBackground))
    }

    func settingsSection(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.appSecondaryText)
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
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: 18, x: 0, y: 10)
        }
    }
}

struct LanguageSettingsView: View {
    let viewModel: SettingsViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                Text("LANGUAGE")
                    .font(.system(size: 12, weight: .bold))
                    .tracking(1)
                    .foregroundStyle(Color.appSecondaryText)
                    .padding(.leading, 4)
                    .padding(.top, 24)

                VStack(spacing: 0) {
                    ForEach(Array(SettingsLanguageChoice.allCases.enumerated()), id: \.element.id) { index, language in
                        Button {
                            viewModel.selectedLanguage = language
                        } label: {
                            HStack(spacing: 14) {
                                Circle()
                                    .fill(Color.appGrayBackground)
                                    .frame(width: 34, height: 34)
                                    .overlay {
                                        PlatformIcon(
                                            systemName: "globe",
                                            size: 13,
                                            weight: .semibold,
                                            color: Color.appPrimaryText
                                        )
                                    }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(language.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Color.appPrimaryText)

                                    if let subtitle = language.subtitle {
                                        Text(subtitle)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Color.appSecondaryText)
                                    }
                                }

                                Spacer()

                                if viewModel.selectedLanguage == language {
                                    PlatformIcon(
                                        systemName: "checkmark",
                                        size: 14,
                                        weight: .bold,
                                        color: Color.appPink
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
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.035), radius: 18, x: 0, y: 10)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .background(Color(.systemBackground))
    }
}

struct AboutSettingsView: View {
    let viewModel: SettingsViewModel

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
                .foregroundStyle(Color.appSecondaryText)
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
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: 18, x: 0, y: 10)
        }
    }
}

struct SettingsPlaceholderView: View {
    let destination: SettingsDestination

    var body: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(Color.appGrayBackground)
                .frame(width: 58, height: 58)
                .overlay {
                    PlatformIcon(
                        systemName: "gearshape.fill",
                        size: 22,
                        weight: .semibold,
                        color: Color.appSecondaryText
                    )
                }

            Text(destination.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.appPrimaryText)

            Text(destination.placeholderMessage)
                .font(.system(size: 13))
                .foregroundStyle(Color.appSecondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct SettingsRowView: View {
    let row: SettingsRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .fill(row.iconColor.backgroundColor)
                    .frame(width: 34, height: 34)
                    .overlay {
                        PlatformIcon(
                            systemName: row.systemImage,
                            size: 13,
                            weight: .semibold,
                            color: row.iconColor.foregroundColor
                        )
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(row.isDestructive ? .red : Color.appPrimaryText)

                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }

                Spacer()

                PlatformIcon(
                    systemName: "chevron.right",
                    size: 12,
                    weight: .semibold,
                    color: Color.appSecondaryText
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
        SettingsView(viewModel: MockSettingsViewModel())
    }
}
#endif
