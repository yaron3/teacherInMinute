//
//  HostedCheckoutService.swift
//  teacher-minute
//
// Shows a hosted payment page — Tranzila's card page, or its Apple Pay page
// while native Apple Pay through Tranzila is not available — in a sheet over
// the app instead of handing it to Safari. The page ends by redirecting to
// `teacherminute://payment-return?…` (the backend's `paymentReturnLink`); the
// sheet catches that navigation, closes, and hands the link back, so the
// caller feeds it to the same `PaymentReturnStore` a deep link would reach.
//
// A WKWebView rather than SFSafariViewController, which would ask "Open in
// app?" on the custom-scheme redirect and stay open, or ASWebAuthenticationSession,
// in which Apple Pay on the web is not known to work. WKWebView supports Apple
// Pay JS (`ApplePaySession`) only while the app injects no script into it —
// so nothing here may add a WKUserScript or call evaluateJavaScript.
//
// iOS only. Android keeps opening the page in the browser (`checkoutURL`).

#if canImport(UIKit) && canImport(WebKit)
import SwiftUI
import UIKit
import WebKit

@MainActor
final class HostedCheckoutService: NSObject {
  static let shared = HostedCheckoutService()
  private override init() {}

  enum Outcome {
    /// The page finished and redirected back to the app with this link.
    case returned(URL)
    /// The buyer closed the sheet before the page sent them back. The
    /// payment may still have gone through, so the caller checks.
    case closed
    /// There was nothing to show the sheet over; the caller falls back to
    /// the browser.
    case unavailable
    /// A card attempt failed and the buyer chose to pay with PayPal instead.
    case switchToPayPal
  }

  /// What the sheet offers when a card attempt fails: PayPal, or another
  /// try. Strings come from the view model.
  struct CardFailureOffer {
    let title: String
    let message: String
    let payPalLabel: String
    let retryLabel: String
  }

  private var continuation: CheckedContinuation<Outcome, Never>?
  private weak var sheet: UIViewController?

  /// Presents `url` in the sheet and waits until the page sends the buyer
  /// back or the buyer closes it. With `cardFailureOffer`, a failed card
  /// attempt the page reports puts that offer up over the page.
  func present(url: URL, closeLabel: String, cardFailureOffer: CardFailureOffer? = nil) async -> Outcome {
    if continuation != nil {
      // Only one checkout runs at a time; close the stale one.
      finish(.closed)
    }
    guard let presenter = Self.topPresenter() else {
      logger.error("[HostedCheckout] no view controller to present the checkout over")
      return .unavailable
    }

    let content = HostedCheckoutSheet(
      url: url,
      closeLabel: closeLabel,
      cardFailureOffer: cardFailureOffer,
      onReturn: { [weak self] returnURL in self?.finish(.returned(returnURL)) },
      onClose: { [weak self] in self?.finish(.closed) },
      onSwitchToPayPal: { [weak self] in self?.finish(.switchToPayPal) }
    )
    let controller = UIHostingController(rootView: content)
    controller.modalPresentationStyle = .pageSheet
    // Dark, like the rest of the app; the page is asked for its dark theme too.
    controller.overrideUserInterfaceStyle = .dark
    controller.presentationController?.delegate = self
    sheet = controller

    logger.info("[HostedCheckout] presenting url=\(url.absoluteString)")
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
      presenter.present(controller, animated: true)
    }
  }

  private func finish(_ outcome: Outcome) {
    guard let continuation else { return }
    self.continuation = nil
    if let sheet, sheet.presentingViewController != nil {
      sheet.dismiss(animated: true)
    }
    sheet = nil
    continuation.resume(returning: outcome)
  }

  /// The view controller at the top of the key window's presentation chain:
  /// presenting from the root fails while anything else is already up.
  private static func topPresenter() -> UIViewController? {
    var top = UIApplication.topMostViewController()
    while let presented = top?.presentedViewController, !presented.isBeingDismissed {
      top = presented
    }
    return top
  }
}

extension HostedCheckoutService: UIAdaptivePresentationControllerDelegate {
  /// Swiping the sheet away is the same as tapping Close.
  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    logger.info("[HostedCheckout] sheet swiped away")
    finish(.closed)
  }
}

/// The payment page on the brand's modal ground, under a bar with Close on it.
private struct HostedCheckoutSheet: View {
  let url: URL
  let closeLabel: String
  let cardFailureOffer: HostedCheckoutService.CardFailureOffer?
  let onReturn: (URL) -> Void
  let onClose: () -> Void
  let onSwitchToPayPal: () -> Void

  @State var showsCardFailureOffer = false

  var body: some View {
    NavigationStack {
      CheckoutWebView(url: url, onReturn: onReturn, onCardFailed: cardFailed)
        .background(AppTheme(colorScheme: .dark).brandModalBackground)
        .ignoresSafeArea(edges: .bottom)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button(closeLabel) {
              trackTap("hosted_checkout_close")
              onClose()
            }
            .accessibilityIdentifier("hosted_checkout_close")
          }
        }
    }
    .alert(
      cardFailureOffer?.title ?? "",
      isPresented: $showsCardFailureOffer,
      presenting: cardFailureOffer
    ) { offer in
      Button(offer.payPalLabel) {
        trackTap("hosted_checkout_card_failed_paypal")
        onSwitchToPayPal()
      }
      Button(offer.retryLabel, role: .cancel) {
        trackTap("hosted_checkout_card_failed_retry")
      }
    } message: { offer in
      Text(offer.message)
    }
    .trackScreen(AnalyticsScreen.hostedCheckout)
  }

  private func cardFailed() {
    guard cardFailureOffer != nil else { return }
    showsCardFailureOffer = true
  }
}

private struct CheckoutWebView: UIViewRepresentable {
  let url: URL
  let onReturn: (URL) -> Void
  let onCardFailed: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(onReturn: onReturn, onCardFailed: onCardFailed)
  }

  func makeUIView(context: Context) -> WKWebView {
    // No user scripts and no evaluateJavaScript: either one turns Apple Pay
    // off for every page this web view loads.
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    webView.navigationDelegate = context.coordinator
    webView.uiDelegate = context.coordinator
    // Clear until the page draws, so the sheet's dark ground shows rather
    // than a white flash.
    webView.isOpaque = false
    webView.backgroundColor = .clear
    webView.scrollView.backgroundColor = .clear
    webView.overrideUserInterfaceStyle = .dark
    webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30))
    return webView
  }

  func updateUIView(_ webView: WKWebView, context: Context) {}

  @MainActor
  final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
    let onReturn: (URL) -> Void
    let onCardFailed: () -> Void
    private var didReturn = false

    init(onReturn: @escaping (URL) -> Void, onCardFailed: @escaping () -> Void) {
      self.onReturn = onReturn
      self.onCardFailed = onCardFailed
    }

    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
      guard let url = navigationAction.request.url else { return .allow }
      let scheme = url.scheme?.lowercased() ?? ""
      if ["http", "https", "about", "blob", "data"].contains(scheme) {
        return .allow
      }
      // The page reporting a failed card attempt (only when opened with
      // client=ios). It stays open for a retry; this is not a return.
      if scheme == "teacherminute", url.host == "checkout-event" {
        let type = URLComponents(url: url, resolvingAgainstBaseURL: false)?
          .queryItems?.first { $0.name == "type" }?.value
        logger.info("[HostedCheckout] page event type=\(type ?? "nil")")
        if type == "card_failed" { onCardFailed() }
        return .cancel
      }
      if PaymentReturnResult(url: url) != nil {
        if !didReturn {
          didReturn = true
          logger.info("[HostedCheckout] page returned url=\(url.absoluteString)")
          onReturn(url)
        }
      } else {
        // tel:, mailto: and the like belong to the system.
        _ = await UIApplication.shared.open(url)
      }
      return .cancel
    }

    /// Links that ask for a new window (`target=_blank`, `window.open`) load
    /// here instead: the sheet is the only window.
    func webView(
      _ webView: WKWebView,
      createWebViewWith configuration: WKWebViewConfiguration,
      for navigationAction: WKNavigationAction,
      windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
      if navigationAction.targetFrame == nil {
        webView.load(navigationAction.request)
      }
      return nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
      logNavigationFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
      logNavigationFailure(error)
    }

    /// A load cancelled because we took over the return link is expected.
    private func logNavigationFailure(_ error: Error) {
      let nsError = error as NSError
      if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
      if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return } // frame load interrupted
      logger.error("[HostedCheckout] page failed to load: \(error.localizedDescription)")
    }
  }
}
#endif
