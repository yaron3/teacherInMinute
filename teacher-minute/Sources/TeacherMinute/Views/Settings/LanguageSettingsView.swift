//
//  LanguageSettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

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
            if AppTheme.isBrand {
                brandPage
            } else {
                standardForm
            }

            if localizationManager.isLoading {
                theme.scrim.opacity(0.18).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(theme.primaryText)
            }
        }
    }

    /// Instant Teacher's look: the languages as rows of a brand card, the
    /// chosen one ticked.
    var brandPage: some View {
        BrandSubpage(
            label: viewModel.settingsTitle,
            title: viewModel.settingsPageTitle(service.localized("Language")),
            backLabel: viewModel.backLabel
        ) {
            BrandPageHero(title: service.localized("Language"))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(SettingsLanguageChoice.allCases) { language in
                    if language != SettingsLanguageChoice.allCases.first {
                        BrandRule()
                    }
                    brandRow(language)
                }
            }
            .brandCard()
            .disabled(localizationManager.isLoading)
        }
    }

    func brandRow(_ language: SettingsLanguageChoice) -> some View {
        Button {
            viewModel.updateLanguage(language)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizedTitle(for: language))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.onDarkFill)
                    if let subtitle = localizedSubtitle(for: language) {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(theme.brandSecondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if viewModel.selectedLanguage == language {
                    Image("brand-check", bundle: .module)
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(theme.brandActionBackground)
                        .frame(width: 18, height: 18)
                }
            }
            .frame(minHeight: 44)
            .tappableFrame()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("language_row_\(language.rawValue)")
    }

    var standardForm: some View {
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
