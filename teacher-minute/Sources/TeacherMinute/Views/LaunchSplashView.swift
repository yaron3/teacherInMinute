import SwiftUI
#if os(Android)
import SkipBridge
#endif

struct LaunchSplashView: View {
  @State var viewModel = LaunchSplashViewModel()

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .top) {
        #if !os(Android)
        artwork
        #endif

        tagline
          .padding(.top, 337)
      }
      .frame(maxWidth: .infinity)
      // The logo's top sits 249pt above the middle of the screen, as in the
      // design, whatever the tagline's length. The native launch screens
      // (Darwin/LaunchScreen.storyboard, Android's splash_background) draw the
      // art at the same spot, so this screen takes over from them without a
      // jump.
      .padding(.top, max(0, proxy.size.height / 2 - 249))
    }
    .background(backdrop)
    .ignoresSafeArea()
    .trackScreen(AnalyticsScreen.launchSplash)
  }

  /// The brand gradient. On Android it comes with the art already on it, from
  /// the drawable Android's own launch window shows (`AndroidSplashArtBridge`):
  /// SwiftUI images load asynchronously there, and would leave the screen
  /// without the art for a moment.
  @ViewBuilder
  private var backdrop: some View {
    #if os(Android)
    if let composer = AndroidSplashArtBridge.composer,
       let art = JavaBackedView(composer.toJavaObject(options: [.kotlincompat])) {
      art
    } else {
      brandGradient
    }
    #else
    brandGradient
    #endif
  }

  private var brandGradient: some View {
    LinearGradient(
      colors: [theme.brandBackgroundTop, theme.brandBackgroundBottom],
      startPoint: .top,
      endPoint: .bottom
    )
  }

  /// The logo over the glow that lights it from behind. Neither is centred on
  /// the screen, so the pair is pinned left-to-right: the art is the same in
  /// both languages, and a Hebrew layout would mirror the offsets.
  private var artwork: some View {
    ZStack(alignment: .top) {
      Image(decorative: "splash-glow", bundle: .module)
        .resizable()
        .frame(width: 340, height: 340)
        .offset(x: -7, y: 38)

      Image(decorative: "brand-logo", bundle: .module)
        .resizable()
        .scaledToFit()
        .frame(width: 375, height: 318)
        .offset(x: 10.5)
    }
    .environment(\.layoutDirection, .leftToRight)
  }

  private var tagline: some View {
    VStack(spacing: 0) {
      taglineLine(viewModel.stuckQuestion, color: theme.onDarkFill)

      // The highlighted phrase shares a line with the rest of the sentence
      // when it fits, as it does in Hebrew. The English sentence is longer and
      // breaks after the highlight instead.
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 6) {
          humanTeacherHighlight
          responseTimePromise
        }
        VStack(spacing: 0) {
          humanTeacherHighlight
          responseTimePromise
        }
      }
    }
    .font(.system(size: 24, weight: .medium))
    .multilineTextAlignment(.center)
    .frame(maxWidth: 313)
  }

  private var humanTeacherHighlight: some View {
    taglineLine(viewModel.humanTeacherHighlight, color: theme.brandHighlightText)
  }

  private var responseTimePromise: some View {
    taglineLine(viewModel.responseTimePromise, color: theme.onDarkFill)
  }

  /// A line of the tagline, at least as tall as a line of Noto Sans Hebrew,
  /// the face the design sets it in. iOS draws Hebrew in SF Hebrew, whose
  /// lines are shorter; without this the second line rides up.
  private func taglineLine(_ text: String, color: Color) -> some View {
    Text(text)
      .foregroundStyle(color)
      .frame(minHeight: 32.7)
  }
}

#if os(iOS)
struct LaunchSplashView_Previews: PreviewProvider {
  static var previews: some View {
    LaunchSplashView()
  }
}
#endif
