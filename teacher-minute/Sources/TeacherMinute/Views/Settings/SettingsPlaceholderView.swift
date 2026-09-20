//
//  SettingsPlaceholderView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct SettingsPlaceholderView: View {
    let destination: SettingsDestination
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
    var body: some View {
        VStack(spacing: 14) {
            Circle()
                .fill(theme.cardBackground)
                .frame(width: 58, height: 58)
                .overlay {
                    PlatformIcon(
                        systemName: "gearshape.fill",
                        size: 22,
                        weight: .semibold,
                        color: theme.secondaryText
                    )
                }

            Text(destination.title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(theme.primaryText)

            Text(destination.placeholderMessage)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
