// swift-tools-version: 6.1
// This is a Skip (https://skip.dev) package.
import PackageDescription

let package = Package(
    name: "teacher-minute",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TeacherMinute", type: .dynamic, targets: ["TeacherMinute"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.8.13"),
        .package(url: "https://source.skip.tools/skip-fuse-ui.git", from: "1.0.0"),
        .package(url: "https://github.com/skiptools/skip-firebase.git", from: "0.16.0"),
        .package(url: "https://github.com/google/GoogleSignIn-iOS", from: "9.0.0"),
        // Capped below 2.17.0, which is the release that replaced SwiftProtobuf
        // with a vendored nanopb (the CLiveKitProto target). Its generated
        // headers are nanopb 0.4 output and demand PB_PROTO_HEADER_VERSION 40,
        // but the `nanopb` module in this graph belongs to firebase-ios-sdk,
        // which pins firebase/nanopb "2.30910.0"..<"2.30911.0" — still the
        // 0.3.9.x line, header version 30, and no `pb_msgdesc_t`. LiveKit's
        // `#include <pb.h>` resolves to Firebase's module rather than its own
        // vendored copy, so CLiveKitProto fails to build with errors in files
        // none of ours include. Only one nanopb can win per package identity,
        // and Firebase's range is the narrower one, so the cap stays until
        // Firebase moves to nanopb 0.4.
        .package(url: "https://github.com/livekit/client-sdk-swift.git", "2.0.0" ..< "2.17.0"),
        .package(url: "https://github.com/braintree/braintree_ios", from: "7.9.0"),
    ],
    targets: [
        .target(
            name: "TeacherMinute",
            dependencies: [
                .product(name: "SkipFuseUI", package: "skip-fuse-ui"),
                .product(name: "SkipFirebaseCore", package: "skip-firebase"),
                .product(name: "SkipFirebaseAuth", package: "skip-firebase"),
                .product(name: "SkipFirebaseFirestore", package: "skip-firebase"),
                .product(name: "SkipFirebaseStorage", package: "skip-firebase"),
                .product(name: "SkipFirebaseDatabase", package: "skip-firebase"),
                .product(name: "SkipFirebaseMessaging", package: "skip-firebase"),
                .product(name: "SkipFirebaseRemoteConfig", package: "skip-firebase"),
                .product(name: "SkipFirebaseAnalytics", package: "skip-firebase"),
                .product(name: "SkipFirebaseCrashlytics", package: "skip-firebase"),
                .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS", condition: .when(platforms: [.iOS])),
                .product(name: "LiveKit", package: "client-sdk-swift", condition: .when(platforms: [.iOS])),
                .product(name: "BraintreeCore", package: "braintree_ios", condition: .when(platforms: [.iOS])),
                .product(name: "BraintreeApplePay", package: "braintree_ios", condition: .when(platforms: [.iOS])),
                .product(name: "BraintreePayPal", package: "braintree_ios", condition: .when(platforms: [.iOS])),
            ],
            // KaTeX is copied rather than processed: its stylesheet reaches the
            // font files by relative path, which only survives if the folder
            // does. Bundling it is what lets a formula draw with no network.
            resources: [.process("Resources"), .copy("KaTeX")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .testTarget(
            name: "TeacherMinuteTests",
            dependencies: ["TeacherMinute"]
        ),
    ]
)
