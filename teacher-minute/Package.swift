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
                .product(name: "SkipFirebaseRemoteConfig", package: "skip-firebase"),
                .product(name: "GoogleSignInSwift", package: "GoogleSignIn-iOS", condition: .when(platforms: [.iOS])),
            ],
            resources: [.process("Resources")],
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .testTarget(
            name: "TeacherMinuteTests",
            dependencies: ["TeacherMinute"]
        ),
    ]
)
