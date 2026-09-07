//
//  AccountSecuritySettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct AccountSecuritySettingsView: View {
    let viewModel: any SettingsViewModeling
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    var body: some View {
        ZStack {
            List {
                SettingsSectionView(section: viewModel.accountSecuritySection) { row in
                    viewModel.select(row)
                }
            }

            if viewModel.isLoading {
                theme.scrim.opacity(0.18).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(theme.primaryText)
            }
        }
    }
}
