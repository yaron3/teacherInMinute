// swift-tools-version: 5.9
//
// PayPal's native iOS checkout SDK — only its CorePayments and PayPalPayments
// modules, copied unmodified from https://github.com/paypal/paypal-ios at tag
// 3.2.0 (commit 7eb8f7b7f9162e8f8114abae7f5dba9b525eae64), Apache-2.0 (LICENSE).
//
// Why a copy rather than the package: every paypal-ios release declares a
// `PPRiskMagnes` binary target (3.0 inside the package, 3.1+ through
// paypal-risk-ios), and braintree_ios ships a target of the same name.
// SwiftPM refuses two targets with one name anywhere in the graph, so the two
// SDKs cannot both be package dependencies. These two modules never use
// PPRiskMagnes (only FraudProtection does), so they build on their own.
//
// To update: copy Sources/CorePayments and Sources/PayPalPayments from the new
// tag over these, check they still import nothing but Apple frameworks and
// CorePayments, and update the tag and commit above.

import PackageDescription

let package = Package(
    name: "PayPalCheckout",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "CorePayments", targets: ["CorePayments"]),
        .library(name: "PayPalPayments", targets: ["PayPalPayments"]),
    ],
    targets: [
        .target(
            name: "CorePayments",
            dependencies: [],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
        .target(
            name: "PayPalPayments",
            dependencies: ["CorePayments"],
            resources: [.copy("PrivacyInfo.xcprivacy")]
        ),
    ]
)
