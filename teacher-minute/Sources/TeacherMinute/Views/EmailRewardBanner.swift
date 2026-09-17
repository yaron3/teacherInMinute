//
//  EmailRewardBanner.swift
//  teacher-minute
//
//  The verify-your-email offer on the student home and teacher dashboard, and,
//  for a teacher, the welcome bonus still running once it has been earned.
//  Renders nothing otherwise. Its dialogs are attached separately, at the
//  screen root, with `emailRewardDialogs(_:)` — on Android a dialog attached to
//  a view this small would be laid out inside it.
//

import SwiftUI

struct EmailRewardBanner: View {
  let viewModel: EmailRewardViewModel
  /// Called after a reward was credited, so the screen can reload its balance.
  var onGranted: () -> Void = {}
  /// Space above the card, applied only when there is a card to show.
  var topPadding: CGFloat = 0

  @Environment(\.scenePhase) var scenePhase
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    // The stack stays in the tree while it is empty, so the check below still
    // runs for a user who has nothing to be shown yet.
    VStack(spacing: 0) {
      content
    }
      .task {
        await viewModel.refresh()
      }
      // Coming back from the mail app is the usual moment the link was opened.
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        Task { await viewModel.refresh() }
      }
      .onChange(of: viewModel.grantVersion) { _, _ in
        onGranted()
      }
  }

  @ViewBuilder
  var content: some View {
    if viewModel.showsVerifyBanner, let offer = viewModel.offerDescription {
      verifyCard(offer: offer)
        .padding(.top, topPadding)
    } else if viewModel.showsTeacherBonus {
      bonusCard
        .padding(.top, topPadding)
    }
  }

  func verifyCard(offer: String) -> some View {
    FlatCard(filled: theme.accentBackground) {
      VStack(alignment: .leading, spacing: 12) {
        HStack(alignment: .top, spacing: 12) {
          PlatformIcon(systemName: "envelope.badge.fill", size: 22, weight: .semibold, color: theme.accent)
          VStack(alignment: .leading, spacing: 4) {
            Text(viewModel.verifyEmailTitle)
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(theme.primaryText)
            Text(offer)
              .font(.system(size: 13))
              .foregroundStyle(theme.secondaryText)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        HStack(spacing: 10) {
          Button {
            Task { await viewModel.resendTapped() }
          } label: {
            Text(viewModel.resendLabel)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(theme.accent)
              .frame(maxWidth: .infinity)
              .frame(height: 40)
              .background(theme.cardBackground)
              .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
          }
          .buttonStyle(.plain)

          Button {
            Task { await viewModel.checkVerificationTapped() }
          } label: {
            Text(viewModel.checkVerificationLabel)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(theme.onAccentText)
              .frame(maxWidth: .infinity)
              .frame(height: 40)
              .background(theme.accent)
              .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
          }
          .buttonStyle(.plain)
        }
        .disabled(viewModel.isWorking)
        .opacity(viewModel.isWorking ? 0.6 : 1)
      }
    }
  }

  var bonusCard: some View {
    FlatCard(filled: theme.positiveBackground) {
      HStack(alignment: .top, spacing: 12) {
        PlatformIcon(systemName: "gift.fill", size: 20, weight: .semibold, color: theme.positive)
        VStack(alignment: .leading, spacing: 4) {
          Text(viewModel.teacherBonusTitle)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.primaryText)
          Text(viewModel.teacherBonusDescription)
            .font(.system(size: 13))
            .foregroundStyle(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}

extension View {
  /// Presents the reward banner's dialogs. Attach at the screen root.
  func emailRewardDialogs(_ viewModel: EmailRewardViewModel) -> some View {
    appDialog(
      viewModel.dialog?.title ?? "",
      isPresented: Binding(
        get: { viewModel.dialog != nil },
        set: { if !$0 { viewModel.dismissDialog() } }
      ),
      message: viewModel.dialog?.message,
      actions: [AppDialogAction(viewModel.okLabel)]
    )
  }
}
