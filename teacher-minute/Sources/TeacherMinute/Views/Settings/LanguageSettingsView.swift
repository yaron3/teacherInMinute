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
