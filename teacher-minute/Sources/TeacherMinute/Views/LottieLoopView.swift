//
//  LottieLoopView.swift
//  teacher-minute
//
//  A Lottie animation from the module's resources, looping for as long as it
//  is on screen. lottie-ios draws it on iOS; on Android lottie-compose draws
//  the same file (`AndroidLottieView.kt`), handed over as its JSON.
//

import SwiftUI
#if os(Android)
import SkipBridge
#elseif canImport(Lottie)
import Lottie
#endif

struct LottieLoopView: View {
  /// The animation's file in Resources, without its `.json`.
  let name: String

  #if os(Android)
  @State var composer: AndroidJavaObject?
  #endif

  var body: some View {
    animation
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  #if os(Android)
  @ViewBuilder
  private var animation: some View {
    if let composer,
       let backed = JavaBackedView(composer.toJavaObject(options: [.kotlincompat])) {
      backed
    } else {
      Color.clear
        .task {
          composer = AndroidLottieBridge.makeComposer(named: name)
        }
    }
  }
  #elseif canImport(Lottie)
  private var animation: some View {
    LottieView(animation: LottieAnimation.named(name, bundle: .module))
      .looping()
      .resizable()
  }
  #else
  private var animation: some View {
    Color.clear
  }
  #endif
}

#if os(Android)
/// `AndroidLottieView.kt`, for `LottieLoopView` to embed.
enum AndroidLottieBridge {
  private static let viewClass = try! JClass(name: "teacher/minute/AndroidLottieView")
  private static let createMethod = viewClass.getStaticMethodID(
    name: "create",
    sig: "(Ljava/lang/String;)Lskip/ui/ComposeView;"
  )!

  /// Read here rather than in Kotlin: the file is the Swift module's
  /// resource, the same one iOS reads.
  static func makeComposer(named name: String) -> AndroidJavaObject? {
    guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
          let json = try? String(contentsOf: url, encoding: .utf8) else {
      logger.error("[Lottie][Android] no animation named \(name) in the bundle")
      return nil
    }
    return jniContext {
      do {
        return try viewClass.callStatic(
          method: createMethod,
          options: [.kotlincompat],
          args: [json.toJavaParameter(options: [.kotlincompat])]
        )
      } catch {
        logger.error("[Lottie][Android] failed to create the animation view: \(error)")
        return nil
      }
    }
  }
}
#endif
