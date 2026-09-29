//
//  StudentSettingsView.swift
//  teacher-minute
//
//  Instant Teacher's settings, as its design draws them: the design's four
//  rows, then in a card of the same style the settings it leaves out. It is
//  the root of `SettingsView`'s navigation stack for a student, and runs on
//  the same view model, which routes a tapped row as it always has.
//

import SwiftUI

struct StudentSettingsView: View {
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
      rowsCard(viewModel.studentSettingsRows)
      rowsCard(viewModel.studentMoreSettingsRows)
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
    VStack(alignment: .leading, spacing: 12) {
      ForEach(rows) { row in
        if row.id != rows.first?.id {
          BrandRule()
        }
        settingsRow(row)
      }
    }
    .brandCard()
  }

  /// The icon at the start, then the name and what it holds. As designed,
  /// only Preferences and Notifications carry the chevron.
  private func settingsRow(_ row: SettingsRow) -> some View {
    Button {
      viewModel.select(row)
    } label: {
      HStack(spacing: 12) {
        rowIcon(row)
          .frame(width: 40, height: 40)

        VStack(alignment: .leading, spacing: 4) {
          Text(row.title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(row.isDestructive ? theme.danger : theme.onDarkFill)
          if let subtitle = row.subtitle {
            Text(subtitle)
              .font(.system(size: 13))
              .foregroundStyle(theme.brandSecondaryText)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if row.action == .appPreferences || row.action == .notifications {
          BrandForwardChevron()
        }
      }
      .tappableFrame()
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("settings_row_\(row.action.id)")
  }

  /// The design's icon where it has one; a system symbol for the rows it
  /// leaves out.
  @ViewBuilder
  private func rowIcon(_ row: SettingsRow) -> some View {
    if let asset = designedIcon(for: row.action) {
      Image(asset, bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.onDarkFill)
    } else {
      Image(systemName: row.systemImage)
        .resizable()
        .scaledToFit()
        .foregroundStyle(row.isDestructive ? theme.danger : theme.onDarkFill)
        .frame(width: 18, height: 18)
    }
  }

  private func designedIcon(for action: SettingsAction) -> String? {
    switch action {
    case .appPreferences: "brand-settings-preferences"
    case .language: "brand-settings-language"
    case .notifications: "brand-settings-notifications"
    case .privacyControls: "brand-settings-privacy"
    default: nil
    }
  }
}

#if os(iOS)
#Preview {
  NavigationStack {
    StudentSettingsView(viewModel: MockSettingsViewModel(role: .student))
  }
}
#endif
