//
//  PaymentMethodSheet.swift
//  teacher-minute
//
//  Payment-method chooser for checkout. Apple Pay renders Apple's official
//  PKPaymentButton (ApplePayButtonView) rather than a plain text button, per
//  the Apple Pay Identity Guidelines / App Review Guideline 3.1.1.
//

import SwiftUI

struct PaymentMethodSheet: View {
  let methods: [PaymentMethod]
  let theme: AppTheme
  let onSelect: (PaymentMethod) -> Void

  @Environment(\.dismiss) var dismiss

  var body: some View {
    VStack(spacing: 16) {
      Text(LocalizationSupport.localized("Choose a payment method"))
        .font(.headline)
        .foregroundStyle(theme.appPrimaryText)
        .padding(.top, 20)

      VStack(spacing: 12) {
        ForEach(methods, id: \.self) { method in
          row(for: method)
        }
      }
      .padding(.horizontal, 20)

      Button(LocalizationSupport.localized("Cancel")) {
        dismiss()
      }
      .foregroundStyle(theme.appSecondaryText)
      .padding(.top, 4)

      Spacer()
    }
    .presentationDetents([.medium])
  }

  @ViewBuilder
  private func row(for method: PaymentMethod) -> some View {
#if canImport(UIKit)
    if method == .applePay {
      ApplePayButtonView { onSelect(method) }
        .frame(height: 48)
    } else if method == .paypal {
      payPalRow()
    } else {
      standardRow(for: method)
    }
#else
    if method == .paypal {
      payPalRow()
    } else {
      standardRow(for: method)
    }
#endif
  }

  /// PayPal's branded button: same geometry as `standardRow` (full width, same
  /// padding, radius and border weight), but PayPal's own colours and lockup
  /// instead of the app theme — brand marks must not adapt to light/dark, so
  /// these colours are fixed rather than drawn from `theme`.
  private func payPalRow() -> some View {
    Button {
      onSelect(.paypal)
    } label: {
      HStack(spacing: 6) {
        Text(LocalizationSupport.localized("Pay with"))
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(Self.payPalInk)
        payPalLockup
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 14)
      .background(Self.payPalGold)
      .overlay(
        RoundedRectangle(cornerRadius: 12)
          .stroke(Self.payPalInk, lineWidth: 1)
      )
      .cornerRadius(12)
    }
  }

  /// The PayPal monogram followed by the two-tone wordmark.
  private var payPalLockup: some View {
    HStack(spacing: 3) {
      // Monogram: the light-blue P sits in front of and below the navy one.
      ZStack(alignment: .leading) {
        Text(verbatim: "P")
          .font(.system(size: 17, weight: .bold))
          .italic()
          .foregroundStyle(Self.payPalNavy)
        Text(verbatim: "P")
          .font(.system(size: 17, weight: .bold))
          .italic()
          .foregroundStyle(Self.payPalBlue)
          .offset(x: 4, y: 2)
      }
      .padding(.trailing, 4)

      HStack(spacing: 0) {
        Text(verbatim: "Pay")
          .foregroundStyle(Self.payPalNavy)
        Text(verbatim: "Pal")
          .foregroundStyle(Self.payPalBlue)
      }
      .font(.system(size: 17, weight: .bold))
      .italic()
    }
  }

  // PayPal brand palette (fixed in both colour schemes).
  private static let payPalGold = Color(red: 255 / 255, green: 196 / 255, blue: 57 / 255)
  private static let payPalNavy = Color(red: 37 / 255, green: 59 / 255, blue: 128 / 255)
  private static let payPalBlue = Color(red: 23 / 255, green: 155 / 255, blue: 215 / 255)
  private static let payPalInk = Color(red: 28 / 255, green: 28 / 255, blue: 28 / 255)

  private func standardRow(for method: PaymentMethod) -> some View {
    Button {
      onSelect(method)
    } label: {
      Text(method.displayName)
        .font(.system(size: 16, weight: .semibold))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .foregroundStyle(theme.appPrimaryText)
        .background(theme.appCardBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(theme.appBorder, lineWidth: 1)
        )
        .cornerRadius(12)
    }
  }
}
