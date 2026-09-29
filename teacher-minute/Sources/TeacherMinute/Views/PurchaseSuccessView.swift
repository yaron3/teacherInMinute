import SwiftUI

/// The confirmation after minutes were bought: what was added, the balance
/// now, and the way back to the question.
struct PurchaseSuccessView: View {
  let viewModel: any StudentHomeViewModeling
  let summary: PurchaseSummary
  let onDone: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    ZStack {
      BrandScreenBackground(streaks: .purchase)

      VStack(spacing: 0) {
        confirmation
        Spacer(minLength: 24)
        detailsCard
        Spacer(minLength: 24)
        returnActions
      }
      .padding(.horizontal, 24)
      .padding(.top, 36)
      .padding(.bottom, 26)
    }
    .onAppear {
      viewModel.logPurchaseSuccessShown(summary)
    }
  }

  private var confirmation: some View {
    // The emblem's art runs 5pt below its 142pt circle, for a glow neither
    // platform's SVG renderer draws; the gap under it gives the 5pt back.
    VStack(spacing: 17) {
      Image(decorative: "purchase-success-emblem", bundle: .module)
        .resizable()
        .frame(width: 142, height: 147)

      VStack(spacing: 8) {
        Text(viewModel.minutesAddedTitle)
          .font(.system(size: 28, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .frame(maxWidth: .infinity)
        Text(viewModel.minutesAddedMessage)
          .font(.system(size: 15))
          .foregroundStyle(theme.brandSecondaryText)
          .lineSpacing(4)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: 300)
      }
      .multilineTextAlignment(.center)
    }
  }

  private var detailsCard: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack(spacing: 8) {
        Text(viewModel.topUpDetailsTitle)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
        Spacer(minLength: 0)
        completedPill
      }

      HStack(spacing: 12) {
        metric(
          value: viewModel.purchasedMinutesValue(summary),
          valueColor: theme.onDarkFill,
          label: viewModel.minutesPurchasedLabel
        ) {
          Image("brand-plus", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(theme.brandActionBackground)
            .frame(width: 16, height: 16)
            .frame(width: 24, height: 24)
            .background(theme.brandActionBackground.opacity(0.12))
            .clipShape(Circle())
        }
        metric(
          value: "\(viewModel.remainingMinutes)",
          valueColor: theme.brandActionBackground,
          label: viewModel.updatedBalanceLabel
        ) {
          Image("minutes-timer", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(theme.onDarkFill)
            .frame(width: 24, height: 24)
        }
      }
    }
    .padding(20)
    .background(theme.brandPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
    .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 18)
  }

  private var completedPill: some View {
    HStack(spacing: 5) {
      Image("brand-check-circle", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.brandSuccess)
        .frame(width: 14, height: 14)
        .accessibilityHidden(true)
      Text(viewModel.completedLabel)
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(theme.brandSuccess)
    }
    .padding(.horizontal, 9)
    .padding(.vertical, 5)
    .background(theme.brandSuccess.opacity(0.1))
    .clipShape(Capsule())
  }

  private func metric<Icon: View>(
    value: String,
    valueColor: Color,
    label: String,
    @ViewBuilder icon: () -> Icon
  ) -> some View {
    VStack(spacing: 5) {
      icon()
      Text(value)
        .font(.system(size: 26, weight: .bold))
        .foregroundStyle(valueColor)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
      Text(label)
        .font(.system(size: 12))
        .foregroundStyle(theme.brandSecondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity)
    .background(theme.brandCardSurface)
    .clipShape(RoundedRectangle(cornerRadius: 14))
  }

  private var returnActions: some View {
    VStack(spacing: 10) {
      HStack(spacing: 8) {
        Image("brand-session", bundle: .module)
          .renderingMode(.template)
          .resizable()
          .foregroundStyle(theme.onDarkFill)
          .frame(width: 25, height: 24)
          .accessibilityHidden(true)
        Text(viewModel.readyForNextQuestionText)
          .font(.system(size: 12))
          .foregroundStyle(theme.brandSecondaryText)
      }

      BrandPrimaryButton(title: viewModel.backToQuestionLabel) {
        onDone()
      }
      .accessibilityIdentifier("purchase_success_done")
    }
  }
}
