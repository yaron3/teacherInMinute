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
    } else {
      standardRow(for: method)
    }
#else
    standardRow(for: method)
#endif
  }

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
