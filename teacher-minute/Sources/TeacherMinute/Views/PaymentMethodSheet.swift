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
  var savedPayPalEmail: String? = nil
  let onSelect: (PaymentMethod) -> Void

  @Environment(\.dismiss) var dismiss

  var body: some View {
    VStack(spacing: 16) {
      Text(LocalizationSupport.localized("Choose a payment method"))
        .font(.headline)
        .foregroundStyle(theme.primaryText)
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
      .foregroundStyle(theme.secondaryText)
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
    } else if method == .savedPayPal {
      payPalRow(savedEmail: savedPayPalEmail)
    } else if method == .googlePay {
      googlePayRow()
    } else {
      standardRow(for: method)
    }
#else
    if method == .paypal {
      payPalRow()
    } else if method == .googlePay {
      googlePayRow()
    } else {
      standardRow(for: method)
    }
#endif
  }

  /// PayPal's branded button: same geometry as `standardRow` (full width, same
  /// padding, radius and border weight), but PayPal's own colours and lockup
  /// instead of the app theme — brand marks must not adapt to light/dark, so
  /// these colours are fixed rather than drawn from `theme`.
  ///
  /// When `savedEmail` is set, this selects `.savedPayPal` instead of
  /// `.paypal` — same PayPal branding, but the saved account's email is shown
  /// and tapping charges it directly rather than opening a login redirect.
  private func payPalRow(savedEmail: String? = nil) -> some View {
    Button {
      onSelect(savedEmail == nil ? .paypal : .savedPayPal)
    } label: {
      VStack(spacing: 2) {
        HStack(spacing: 0) {
          Text(verbatim: "Pay")
            .foregroundStyle(Self.payPalNavy)
          Text(verbatim: "Pal")
            .foregroundStyle(Self.payPalBlue)
        }
        .font(.system(size: 17, weight: .bold))
        .italic()
        if let savedEmail {
          Text(savedEmail)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Self.payPalInk.opacity(0.7))
        }
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

  /// Google Pay's dark button, per developers.google.com/pay/api/web/guides/brand-guidelines.
  /// The guidelines forbid custom buttons and any recolouring, retyping or
  /// translation of the mark, so this draws Google's own `dark_gpay` artwork
  /// (bundled unmodified as the google-pay-logo asset) on a black field, with
  /// no label of our own — Google's "plain" button form. `scaledToFit` keeps
  /// the mark's proportions, which resizing must preserve. Geometry otherwise
  /// matches `standardRow`, and the surrounding 12pt row spacing plus 20pt
  /// horizontal padding satisfy the 8dp minimum clear space.
  private func googlePayRow() -> some View {
    Button {
      onSelect(.googlePay)
    } label: {
      Image("google-pay-logo", bundle: .module)
        .resizable()
        .scaledToFit()
        .frame(height: 20)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.black)
        .cornerRadius(12)
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
        .foregroundStyle(theme.primaryText)
        .background(theme.cardBackground)
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(theme.controlBorder, lineWidth: 1)
        )
        .cornerRadius(12)
    }
  }
}
