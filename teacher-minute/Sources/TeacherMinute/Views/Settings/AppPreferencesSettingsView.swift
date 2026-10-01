//
//  AppPreferencesSettingsView.swift
//  teacher-minute
//
//  The preferences, as Instant Teacher's design draws them: the session type a
//  student's question starts with — for a teacher, their availability when
//  the app opens — the currency, and the appearance.
//

import SwiftUI

struct AppPreferencesSettingsView: View {
  let viewModel: any SettingsViewModeling
  @AppStorage(SessionPreferences.defaultQuestionTypeKey) var defaultQuestionType = ConversationType.audio.rawValue
  @AppStorage(TeacherPresencePreferences.launchPresenceKey) var launchPresence = TeacherPresencePreferences.defaultLaunchPresence.rawValue
  @AppStorage("appearanceMode") var appearanceMode = "system"

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    BrandSubpage(
      label: viewModel.settingsTitle,
      title: viewModel.preferencesHeaderTitle,
      backLabel: viewModel.backLabel
    ) {
      BrandPageHero(title: viewModel.preferencesTitle, subtitle: viewModel.settingsSubtitle)
      card
    }
  }

  private var card: some View {
    VStack(alignment: .leading, spacing: 12) {
      if viewModel.role == .teacher {
        launchPresenceSection
      } else {
        sessionTypeSection
      }

      BrandRule()

      VStack(alignment: .leading, spacing: 8) {
        sectionTitle(viewModel.currencySectionTitle, size: 17)
        HStack(spacing: 12) {
          Text(viewModel.currencySectionTitle)
            .font(.system(size: 17))
            .foregroundStyle(theme.onDarkFill)
          Spacer(minLength: 0)
          Text(viewModel.currencyValueLabel)
            .font(.system(size: 16))
            .foregroundStyle(theme.brandSecondaryText)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        footnote(viewModel.currencyFooterText)
      }

      BrandRule()

      VStack(alignment: .leading, spacing: 8) {
        sectionTitle(viewModel.appearanceSectionTitle, size: 17)
        BrandOptionPicker(
          options: ["system", "light", "dark"],
          selection: appearanceMode,
          title: appearanceTitle,
          outlinesUnselected: false
        ) { mode in
          appearanceMode = mode
        }
      }
    }
    .brandCard()
  }

  private var sessionTypeSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionTitle(viewModel.defaultSessionTypeSectionTitle, size: 16)
      BrandOptionPicker(
        options: ConversationType.allCases,
        selection: ConversationType(rawValue: defaultQuestionType) ?? .audio,
        title: { $0.displayName }
      ) { type in
        defaultQuestionType = type.rawValue
      }
      footnote(viewModel.defaultSessionTypeFooterText)
    }
  }

  /// Whether the teacher comes online by themselves when the app opens.
  private var launchPresenceSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      sectionTitle(viewModel.launchPresenceSectionTitle, size: 16)
      BrandOptionPicker(
        options: TeacherLaunchPresence.allCases,
        selection: TeacherLaunchPresence(rawValue: launchPresence) ?? TeacherPresencePreferences.defaultLaunchPresence,
        title: { $0.title }
      ) { presence in
        launchPresence = presence.rawValue
      }
      footnote(viewModel.launchPresenceFooterText)
    }
  }

  private func appearanceTitle(_ mode: String) -> String {
    switch mode {
    case "light": viewModel.appearanceLightLabel
    case "dark": viewModel.appearanceDarkLabel
    default: viewModel.appearanceSystemLabel
    }
  }

  private func sectionTitle(_ title: String, size: CGFloat) -> some View {
    Text(title)
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(theme.brandSecondaryText)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func footnote(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 13))
      .foregroundStyle(theme.brandSecondaryText)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

#if os(iOS)
#Preview("Student") {
  NavigationStack {
    AppPreferencesSettingsView(viewModel: MockSettingsViewModel(role: .student))
  }
}

#Preview("Teacher") {
  NavigationStack {
    AppPreferencesSettingsView(viewModel: MockSettingsViewModel(role: .teacher))
  }
}
#endif
