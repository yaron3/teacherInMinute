import SwiftUI

/// Buying minutes: a package, a way to pay, and the total, then — once the
/// payment is through — the confirmation (`PurchaseSuccessView`).
///
/// It stands over the student's home rather than being pushed onto its
/// stack. The home keeps the checkout's machinery running underneath — the
/// browser hand-off, the return from it, the spinner and the payment
/// dialogs — and on Android a screen under a pushed one is not composed, so
/// none of that would run while this was on top.
struct MinutesPurchaseView: View {
  let viewModel: any StudentHomeViewModeling
  let onClose: () -> Void

  @State var selectedOptionID: String?
  @State var selectedMethod: PaymentMethod?
  @State var showsMethodPicker = false

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    ZStack {
      if let summary = viewModel.purchaseSummary {
        PurchaseSuccessView(
          viewModel: viewModel,
          summary: summary,
          onDone: {
            viewModel.consumePurchaseSummaryAndPaymentResult()
            onClose()
          }
        )
      } else {
        purchase
      }
    }
    .environment(\.colorScheme, .dark)
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    .sheet(isPresented: $showsMethodPicker) {
      if let option = selectedOption {
        PaymentMethodSheet(
          viewModel: viewModel,
          methods: viewModel.supportedPaymentMethods(for: option),
          theme: AppTheme(colorScheme: colorScheme),
          savedPayPalEmail: viewModel.savedPayPalEmail
        ) { method in
          selectedMethod = method
          showsMethodPicker = false
        }
      }
    }
    .onAppear {
      viewModel.logPurchaseScreenShown()
    }
  }

  private var purchase: some View {
    ZStack {
      BrandScreenBackground(streaks: .purchase)

      // The design's cyan haze, in the bottom right corner in either language.
      Image(decorative: "brand-ambient-glow", bundle: .module)
        .resizable()
        .frame(width: 180, height: 180)
        .offset(x: 58, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .environment(\.layoutDirection, .leftToRight)
        .allowsHitTesting(false)
        .ignoresSafeArea()

      ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: 24) {
          header
          packageSection
          paymentSection
          summaryCard
          payActions
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 24)
      }
    }
  }

  // MARK: - Header

  private var header: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(viewModel.purchaseTitle)
          .font(.system(size: 23, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
        Text(viewModel.purchaseSubtitle)
          .font(.system(size: 13))
          .foregroundStyle(theme.brandSecondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
      BrandBackButton(accessibilityLabel: viewModel.purchaseBackLabel) {
        onClose()
      }
    }
  }

  // MARK: - Packages

  private var packageSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Text(viewModel.choosePackageTitle)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
        Spacer(minLength: 0)
        balancePill
      }

      if viewModel.pricingOptions.count > 3 {
        ScrollView(.horizontal, showsIndicators: false) {
          packageRow(cardWidth: 104)
        }
      } else {
        packageRow(cardWidth: nil)
      }
    }
  }

  private var balancePill: some View {
    HStack(spacing: 6) {
      Image("minutes-timer", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.onDarkFill)
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
      Text(viewModel.purchaseBalanceText)
        .font(.system(size: 12, weight: .bold))
        .foregroundStyle(theme.brandActionBackground)
        .lineLimit(1)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(theme.brandActionBackground.opacity(0.12))
    .clipShape(Capsule())
  }

  private func packageRow(cardWidth: CGFloat?) -> some View {
    HStack(spacing: 10) {
      ForEach(viewModel.pricingOptions) { option in
        packageCard(option, width: cardWidth)
      }
    }
  }

  private func packageCard(_ option: PricingOption, width: CGFloat?) -> some View {
    let isSelected = option.id == selectedOption?.id
    return Button {
      selectedOptionID = option.id
    } label: {
      VStack(spacing: 0) {
        recommendation(for: option)
        Spacer(minLength: 4)
        VStack(spacing: 0) {
          Text(viewModel.packageQuantityText(for: option))
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(isSelected ? theme.brandActionBackground : theme.onDarkFill)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(minHeight: 32)
          Text(viewModel.packageUnitText(for: option))
            .font(.system(size: 13))
            .foregroundStyle(theme.brandSecondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        Spacer(minLength: 4)
        VStack(spacing: 2) {
          Text(option.priceText)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(theme.onDarkFill)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
          Text(viewModel.perMinutePriceText(for: option))
            .font(.system(size: 10))
            .foregroundStyle(theme.brandMutedText)
            .lineLimit(1)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 12)
      .frame(maxWidth: width == nil ? .infinity : nil)
      .frame(width: width)
      .frame(height: 158)
      .background {
        // The selected card's glow comes from its shape alone: a shadow on
        // the whole card would copy its figures too, which Android draws.
        ZStack {
          RoundedRectangle(cornerRadius: 14)
            .fill(theme.brandPanelBackground)
            .shadow(color: isSelected ? theme.brandActionBackground.opacity(0.3) : Color.clear, radius: 12, x: 0, y: 6)
          if isSelected {
            RoundedRectangle(cornerRadius: 14)
              .fill(theme.brandActionBackground.opacity(0.12))
          }
        }
      }
      .overlay {
        RoundedRectangle(cornerRadius: 14)
          .stroke(isSelected ? theme.brandActionBackground : theme.brandControlBorder, lineWidth: isSelected ? 2 : 1)
      }
      .overlay(alignment: .topTrailing) {
        Image(decorative: isSelected ? "home-choice-on" : "home-choice-off", bundle: .module)
          .resizable()
          .frame(width: 24, height: 24)
          .padding(6)
      }
      .tappableFrame()
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("purchase_package_\(option.id)")
  }

  /// "Best value" over the package the store recommends; the same height
  /// left empty over the others, so every card's figures line up.
  @ViewBuilder
  private func recommendation(for option: PricingOption) -> some View {
    if option.isHighlighted {
      Text(viewModel.bestValueLabel)
        .font(.system(size: 10, weight: .bold))
        .foregroundStyle(theme.onBrandAction)
        .lineLimit(1)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(theme.brandActionBackground)
        .clipShape(Capsule())
        .frame(height: 22)
    } else {
      Color.clear
        .frame(height: 22)
    }
  }

  // MARK: - Payment method

  private var paymentSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(viewModel.paymentMethodTitle)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(theme.onDarkFill)

      if let method = currentMethod {
        methodCard(method)
      }
    }
  }

  private func methodCard(_ method: PaymentMethod) -> some View {
    HStack(spacing: 10) {
      Text(viewModel.paymentMethodShortName(method))
        .font(.system(size: 14))
        .foregroundStyle(theme.brandSecondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 6)
        .frame(width: 108, height: 52)
        .background(theme.brandBackgroundTop)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(theme.brandControlBorder, lineWidth: 1)
        }

      VStack(alignment: .leading, spacing: 2) {
        Text(viewModel.paymentMethodTitle(method))
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        if method == .savedPayPal, let email = viewModel.savedPayPalEmail {
          Text(email)
            .font(.system(size: 12))
            .foregroundStyle(theme.brandSecondaryText)
            .lineLimit(1)
        }
      }

      Spacer(minLength: 0)

      if availableMethods.count > 1 {
        Button {
          showsMethodPicker = true
        } label: {
          HStack(spacing: 5) {
            Text(viewModel.changePaymentMethodLabel)
              .font(.system(size: 12, weight: .bold))
              .foregroundStyle(theme.brandActionBackground)
            ForwardChevron(color: theme.brandActionBackground)
          }
          .padding(.vertical, 8)
          .tappableFrame()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("purchase_change_method")
      }
    }
    .padding(.leading, 16)
    .padding(.trailing, 14)
    .frame(height: 76)
    .background(theme.brandPanelBackground)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
  }

  // MARK: - Summary

  private var summaryCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(viewModel.purchaseSummaryTitle)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.onDarkFill)

      if let option = selectedOption {
        HStack {
          Text(viewModel.minutesPackageLabel)
            .foregroundStyle(theme.brandSecondaryText)
          Spacer(minLength: 8)
          Text(viewModel.packageSummaryText(for: option))
            .foregroundStyle(theme.onDarkFill)
        }
        .font(.system(size: 14))

        Rectangle()
          .fill(theme.brandDivider)
          .frame(height: 1)

        HStack {
          Text(viewModel.totalToPayLabel)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.onDarkFill)
          Spacer(minLength: 8)
          Text(option.priceText)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(theme.brandActionBackground)
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .brandCard(cornerRadius: 14)
  }

  // MARK: - Paying

  private var payActions: some View {
    VStack(spacing: 8) {
      payButton

      HStack(spacing: 6) {
        Image("brand-lock", bundle: .module)
          .renderingMode(.template)
          .resizable()
          .foregroundStyle(theme.brandMutedText)
          .frame(width: 13, height: 13)
          .accessibilityHidden(true)
        Text(viewModel.securePaymentNote)
          .font(.system(size: 11))
          .foregroundStyle(theme.brandMutedText)
      }
    }
  }

  /// The design's cyan "Pay" for PayPal and cards. Apple Pay and Google Pay
  /// are started from their own buttons, which their brand rules require.
  @ViewBuilder
  private var payButton: some View {
    if let option = selectedOption, let method = currentMethod {
      switch method {
#if canImport(UIKit)
      case .applePay:
        ApplePayButtonView { pay(option, with: method) }
          .frame(height: 56)
          .disabled(viewModel.isStartingCheckout)
#endif
      case .googlePay:
        Button {
          pay(option, with: method)
        } label: {
          Image("google-pay-logo", bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(height: 22)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isStartingCheckout)
      default:
        BrandPrimaryButton(
          title: viewModel.payLabel(for: option),
          isLoading: viewModel.isStartingCheckout
        ) {
          pay(option, with: method)
        }
      }
    }
  }

  private func pay(_ option: PricingOption, with method: PaymentMethod) {
    viewModel.logPurchaseStarted(option, method: method)
    Task { await viewModel.checkout(option, method: method) }
  }

  // MARK: - Choices

  /// The package chosen, or else the one the store recommends, or else the
  /// first.
  private var selectedOption: PricingOption? {
    let options = viewModel.pricingOptions
    return options.first { $0.id == selectedOptionID }
      ?? options.first { $0.isHighlighted }
      ?? options.first
  }

  private var availableMethods: [PaymentMethod] {
    guard let option = selectedOption else { return [] }
    return viewModel.supportedPaymentMethods(for: option)
  }

  /// The method chosen, while the package allows it, or else the first one
  /// the package allows.
  private var currentMethod: PaymentMethod? {
    let methods = availableMethods
    if let selectedMethod, methods.contains(selectedMethod) {
      return selectedMethod
    }
    return methods.first
  }
}

/// A chevron pointing onward in the language's direction: left in Hebrew,
/// as designed.
struct ForwardChevron: View {
  let color: Color
  @Environment(\.layoutDirection) var layoutDirection

  var body: some View {
    Image("brand-chevron", bundle: .module)
      .renderingMode(.template)
      .resizable()
      .foregroundStyle(color)
      .frame(width: 18, height: 18)
      .scaleEffect(x: layoutDirection == .rightToLeft ? 1 : -1, y: 1)
      .accessibilityHidden(true)
  }
}
