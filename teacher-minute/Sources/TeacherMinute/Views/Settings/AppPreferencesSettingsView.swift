//
//  AppPreferencesSettingsView.swift
//  teacher-minute
//
//  The preferences, as Instant Teacher's design draws them: the session type a
//  student's question starts with, and the currency.
//
//  There is no appearance choice: both apps are drawn on the brand's dark
//  ground throughout (see TeacherMinuteApp), so a Light/Dark/System picker
//  saved a value nothing read (IT-26, IT-27).
//

import SwiftUI

struct AppPreferencesSettingsView: View {
  let viewModel: any SettingsViewModeling
  @AppStorage(SessionPreferences.defaultQuestionTypeKey) var defaultQuestionType = ConversationType.audio.rawValue

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
      if viewModel.role != .teacher {
        sessionTypeSection

        BrandRule()
      }

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
