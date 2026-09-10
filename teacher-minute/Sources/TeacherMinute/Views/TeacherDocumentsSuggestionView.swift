//
//  TeacherDocumentsSuggestionView.swift
//  teacher-minute
//
//  A gentle, in-app suggestion shown after a teacher's first lesson (longer than
//  a minute) inviting — but never forcing — them to complete the remaining
//  verification documents that were optional during onboarding (bug #24). The
//  teacher can complete them now or anytime later from Profile.
//

import SwiftUI

struct TeacherDocumentsSuggestionView: View {
    let viewModel: any TeacherDashboardViewModeling
    /// Called when the teacher chooses to complete the documents now.
    let onComplete: () -> Void
    /// Called when the teacher dismisses the suggestion for later.
    let onDismiss: () -> Void

    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.accentBackground)
                .frame(width: 78, height: 78)
                .overlay {
                    PlatformIcon(systemName: "checkmark.seal.fill", size: 34, weight: .semibold, color: theme.accent)
                }
                .shadow(color: theme.accent.opacity(0.12), radius: 24, x: 0, y: 12)

            Text(viewModel.documentsSuggestionTitle)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

            Text(viewModel.documentsSuggestionText)
                .font(.system(size: 14))
                .foregroundStyle(theme.secondaryText)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 12)

            Spacer()

            AuthPrimaryButton(
                title: viewModel.completeNowLabel,
                systemImage: "arrow.right",
                isEnabled: true
            ) {
                onComplete()
            }

            Button {
                onDismiss()
            } label: {
                Text(viewModel.maybeLaterLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .background(Color(.systemBackground))
    }
}
