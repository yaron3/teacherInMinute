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
                    PlatformIcon(systemName: "checkmark.seal.fill", size: 34, weight: .semibold, color: theme.brandActionBackground)
                }

            Text(viewModel.documentsSuggestionTitle)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(theme.onDarkFill)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

            Text(viewModel.documentsSuggestionText)
                .font(.system(size: 15))
                .foregroundStyle(theme.brandSecondaryText)
                .lineSpacing(6)
                .multilineTextAlignment(.center)
                .padding(.top, 12)
                .padding(.horizontal, 12)

            Spacer()

            AuthPrimaryButton(
                title: viewModel.completeNowLabel,
                isEnabled: true
            ) {
                onComplete()
            }

            Button {
                onDismiss()
            } label: {
                Text(viewModel.maybeLaterLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.brandActionBackground)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .screenGround()
        .environment(\.colorScheme, .dark)
    }
}
