import SwiftUI

/// The streaks of light across the bottom of the brand screens, drawn as the
/// design draws them: each streak is the design's own SVG, turned to its angle
/// and placed where the design places it relative to the bottom of the screen,
/// and the set is screened onto whatever is behind it.
///
/// Two of the streaks are softened with an SVG blur filter that neither
/// platform's SVG renderer applies, so that blur is added here. Android blurs
/// from version 12; older versions draw those two sharp.
struct BrandStreaks: View {
  private struct Streak {
    let name: String
    /// The streak's centre in the design's 402×874 frame.
    let center: CGPoint
    /// The SVG's size.
    let size: CGSize
    /// How far the SVG's centre lies off the streak's line, before it is turned.
    let lineOffset: CGFloat
    let angle: Double
    let isFlipped: Bool
    let blur: CGFloat
  }

  private static let streaks = [
    Streak(name: "brand-streak-21", center: CGPoint(x: 293.5, y: 813), size: CGSize(width: 366.531, height: 7),
           lineOffset: -3.5, angle: 162.21, isFlipped: false, blur: 0),
    Streak(name: "brand-streak-04", center: CGPoint(x: -18.873, y: 944.238), size: CGSize(width: 940, height: 3),
           lineOffset: -1.5, angle: 162, isFlipped: true, blur: 0),
    Streak(name: "brand-streak-06", center: CGPoint(x: 205.677, y: 799), size: CGSize(width: 614.02, height: 22.4),
           lineOffset: -1.5, angle: 162.58, isFlipped: false, blur: 4.85),
    Streak(name: "brand-streak-07", center: CGPoint(x: -106.729, y: 831.583), size: CGSize(width: 1481.6, height: 31.6),
           lineOffset: -5, angle: 162, isFlipped: true, blur: 5.4),
  ]

  var body: some View {
    GeometryReader { proxy in
      let scale = proxy.size.width / 402
      ZStack(alignment: .topLeading) {
        ForEach(Self.streaks, id: \.name) { streak in
          streakImage(streak, scale: scale)
            .offset(y: streak.lineOffset * scale)
            .scaleEffect(x: 1, y: streak.isFlipped ? -1 : 1)
            .rotationEffect(.degrees(streak.angle))
            // A point to hang the streak on. Every streak is wider than the
            // screen, and a view that overflows its frame is centred on it on
            // both platforms, where laying it out full size would not be.
            .frame(width: 0, height: 0)
            .offset(
              x: streak.center.x * scale,
              y: proxy.size.height - (874 - streak.center.y) * scale
            )
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
      .compositingGroup()
      .blendMode(.screen)
    }
    // Decoration: the streaks run the same way in either language.
    .environment(\.layoutDirection, .leftToRight)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func streakImage(_ streak: Streak, scale: CGFloat) -> some View {
    let image = Image(decorative: streak.name, bundle: .module)
      .resizable()
      .frame(width: streak.size.width * scale, height: streak.size.height * scale)
    if streak.blur > 0 {
      image.blur(radius: streak.blur * scale)
    } else {
      image
    }
  }
}
