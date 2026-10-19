//
//  AppShare.swift
//  teacher-minute
//
//  Sharing a link to one of the two apps, or to the website, through the
//  system share sheet.
//

import Foundation
#if os(Android)
import SkipBridge
#elseif canImport(UIKit)
import UIKit
#endif

/// What the side menu's Share offers.
enum ShareTarget: Hashable {
  /// One of the two apps, by the role it is built for.
  case app(AuthRole)
  case website

  /// The website, and the same `/student` and `/teacher` links its QR codes
  /// use: firebase.json redirects them to `/?get=…`, where the page sends an
  /// iPhone to the App Store, an Android phone to Google Play, and anything
  /// else to a dialog saying how to download.
  var url: URL {
    switch self {
    case .app(let role): AppShare.websiteURL.appendingPathComponent(role.rawValue)
    case .website: AppShare.websiteURL
    }
  }

  /// Stable, untranslated name for analytics.
  var identifier: String {
    switch self {
    case .app(let role): "\(role.rawValue)_app"
    case .website: "website"
    }
  }
}

enum AppShare {
  /// The site's own domain, which serves the same Firebase Hosting site.
  static let websiteURL = URL(string: "https://moreh-lerega.co.il")!

  /// Opens the system share sheet with `text`.
  @MainActor
  static func share(text: String) {
#if os(Android)
    AndroidShareBridge.shareText(text)
#elseif canImport(UIKit)
    guard var presenter = UIApplication.topMostViewController() else {
      logger.error("[Share] no view controller to present the share sheet from")
      return
    }
    while let presented = presenter.presentedViewController {
      presenter = presented
    }
    let sheet = UIActivityViewController(activityItems: [text], applicationActivities: nil)
    // An iPad shows the sheet as a popover, which needs an anchor.
    sheet.popoverPresentationController?.sourceView = presenter.view
    sheet.popoverPresentationController?.sourceRect = CGRect(
      x: presenter.view.bounds.midX,
      y: presenter.view.bounds.midY,
      width: 0,
      height: 0
    )
    sheet.popoverPresentationController?.permittedArrowDirections = []
    presenter.present(sheet, animated: true)
#endif
  }
}

#if os(Android)
private enum AndroidShareBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidShareManager")
  private static let shareTextMethod = managerClass.getStaticMethodID(
    name: "shareText",
    sig: "(Ljava/lang/String;)V"
  )!

  static func shareText(_ text: String) {
    jniContext {
      do {
        try managerClass.callStatic(
          method: shareTextMethod,
          options: [.kotlincompat],
          args: [text.toJavaParameter(options: [.kotlincompat])]
        )
      } catch {
        logger.error("[Share][Android] failed to open the share sheet: \(error)")
      }
    }
  }
}
#endif
