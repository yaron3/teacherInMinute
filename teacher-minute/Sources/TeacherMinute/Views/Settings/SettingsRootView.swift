//
//  SettingsRootView.swift
//  teacher-minute
//
//  The settings, as Instant Teacher's design draws them: the design's four
//  rows, then in a card of the same style the settings it leaves out. It is
//  the root of `SettingsView`'s navigation stack, in both apps, and runs on
//  the same view model, which routes a tapped row.
//

import SwiftUI

struct SettingsRootView: View {
  let viewModel: any SettingsViewModeling

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    BrandTabScreen {
      VStack(spacing: 0) {
        BrandPageHeader(label: viewModel.settingsTitle, title: viewModel.settingsTitle) {
          BrandMenuButton()
        }
        ZStack {
          ScrollView(.vertical, showsIndicators: false) {
            content
          }
          if viewModel.isLoading {
            ProgressView()
              .progressViewStyle(.circular)
              .scaleEffect(1.4)
              .tint(theme.onDarkFill)
          }
        }
      }
      // On a plain stack inside the screen, not on `BrandTabScreen`; see
      // there.
      .toolbar(.hidden, for: .navigationBar)
    }
  }

  // Split out of `body`, which the type checker would otherwise have to solve
  // in one piece.
  private var content: some View {
    VStack(alignment: .leading, spacing: 16) {
      BrandPageHero(title: viewModel.settingsTitle, subtitle: viewModel.settingsSubtitle)
      rowsCard(viewModel.primarySettingsRows)
      rowsCard(viewModel.moreSettingsRows)
      Text(viewModel.appVersion)
        .font(.system(size: 13))
        .foregroundStyle(theme.brandSecondaryText)
        .frame(maxWidth: .infinity)
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 20)
  }

  private func rowsCard(_ rows: [SettingsRow]) -> some View {
    BrandSettingsRows(rows: rows) { row in
      viewModel.select(row)
    }
  }
}

#if os(iOS)
#Preview("Student") {
  NavigationStack {
    SettingsRootView(viewModel: MockSettingsViewModel(role: .student))
  }
}

#Preview("Teacher") {
  NavigationStack {
    SettingsRootView(viewModel: MockSettingsViewModel(role: .teacher))
  }
}
#endif
