//
//  StudentPreferencesView.swift
//  teacher-minute
//
//  Instant Teacher's preferences, as its design draws them: the session type a
//  question starts with, the currency, and the appearance. The same settings,
//  in the same storage, as `AppPreferencesSettingsView`.
//

import SwiftUI

struct StudentPreferencesView: View {
  let viewModel: any SettingsViewModeling
  @AppStorage(SessionPreferences.defaultQuestionTypeKey) var defaultQuestionType = ConversationType.audio.rawValue
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
#Preview {
  NavigationStack {
    StudentPreferencesView(viewModel: MockSettingsViewModel(role: .student))
  }
}
#endif
