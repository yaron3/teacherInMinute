//
//  AppPreferencesSettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct AppPreferencesSettingsView: View {
    let viewModel: any SettingsViewModeling
    @AppStorage(SessionPreferences.defaultQuestionTypeKey) var defaultQuestionType = ConversationType.audio.rawValue
    @AppStorage(TeacherPresencePreferences.launchPresenceKey) var launchPresence = TeacherPresencePreferences.defaultLaunchPresence.rawValue
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

            if viewModel.role == .teacher {
                Section(
                    header: Text(viewModel.launchPresenceSectionTitle),
                    footer: Text(viewModel.launchPresenceFooterText)
                ) {
                    LaunchPresencePicker(selection: $launchPresence)
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
