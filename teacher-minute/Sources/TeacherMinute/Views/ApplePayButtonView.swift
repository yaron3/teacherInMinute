//
//  ApplePayButtonView.swift
//  teacher-minute
//
//  Wraps PKPaymentButton so the payment-method picker can show Apple's
//  official Apple Pay mark, as required by the Apple Pay Identity Guidelines
//  (App Review Guideline 3.1.1) — a plain text button isn't compliant.
//

#if canImport(UIKit)
import SwiftUI
import PassKit

struct ApplePayButtonView: UIViewRepresentable {
  var action: () -> Void

  func makeUIView(context: Context) -> PKPaymentButton {
    let button = PKPaymentButton(paymentButtonType: .plain, paymentButtonStyle: .automatic)
    button.addTarget(context.coordinator, action: #selector(Coordinator.tapped), for: .touchUpInside)
    button.cornerRadius = 12
    return button
  }

  func updateUIView(_ uiView: PKPaymentButton, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  final class Coordinator: NSObject {
    let action: () -> Void
    init(action: @escaping () -> Void) {
      self.action = action
    }
    @objc func tapped() {
      action()
    }
  }
}
#endif
