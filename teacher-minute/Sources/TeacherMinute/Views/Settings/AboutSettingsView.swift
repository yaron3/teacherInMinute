//
//  AboutSettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

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
