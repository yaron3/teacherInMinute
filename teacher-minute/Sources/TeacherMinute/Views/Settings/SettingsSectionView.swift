//
//  SettingsSectionView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct SettingsSectionView: View {
    let section: SettingsSection
    let onSelect: (SettingsRow) -> Void
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        Section {
            ForEach(section.rows) { row in
                if let destination = row.destination {
                    NavigationLink(value: destination) {
                        SettingsRowView(row: row)
                    }
                } else {
                    Button {
                        onSelect(row)
                    } label: {
                        SettingsRowView(row: row)
                    }
                }
            }
        } header: {
            Text(section.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.primaryText)
        }
    }
}
