//
//  SettingsRowView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct SettingsRowView: View {
    let row: SettingsRow
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    var body: some View {
        HStack(spacing: 14) {
            FlatIconTile(
                systemName: row.systemImage,
                size: 40,
                tint: row.isDestructive ? theme.danger : theme.primaryText
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(row.isDestructive ? theme.danger : theme.primaryText)

                if let subtitle = row.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
