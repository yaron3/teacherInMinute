import SwiftUI

/// Where the student's home puts things, worked out from the screen.
///
/// The design is drawn on a 402×874 screen, and on one that size everything
/// lands where the design puts it. Elsewhere the controls keep their size and
/// their distance from the top, the character's scene keeps its place at the
/// bottom and scales with the width, and the writing panel gives up height —
/// then the scene shrinks — rather than let the two overlap.
struct QuestionHomeLayout {
  let size: CGSize
  /// The status bar's height, which the controls sit under.
  let safeTop: CGFloat
  let safeBottom: CGFloat
  /// The height there is now: less than `size`, the screen's height at
  /// rest, while Android has resized the window for the keyboard.
  var availableHeight: CGFloat
  /// Where a keyboard begins, when one is up on the panel.
  var keyboardTop: CGFloat? = nil

  static let designWidth: CGFloat = 402
  /// The scene's box: from the top of the character's square to the bottom
  /// of the screen.
  static let sceneHeight: CGFloat = 337
  /// From the top of the highest bubble to the bottom of the screen.
  static let sceneVisibleHeight: CGFloat = 291
  static let toggleHeight: CGFloat = 60
  static let buttonHeight: CGFloat = 56
  /// Half the capture button's height, with its two-line label.
  static let captureHalfHeight: CGFloat = 82

  var widthScale: CGFloat { size.width / Self.designWidth }

  var menuTop: CGFloat { safeTop + 3 }
  var toggleTop: CGFloat { safeTop - 1 }
  var toggleWidth: CGFloat { max(0, min(266, size.width - 110)) }

  var panelTop: CGFloat { safeTop + 83 }
  var panelWidth: CGFloat { max(0,size.width - 52) }
  var panelLeading: CGFloat { max(0, (size.width - panelWidth) / 2 - 2) }
  /// The panel's height with no keyboard up.
  var restingPanelHeight: CGFloat {
    let room = size.height - safeTop - 176 - Self.sceneVisibleHeight * widthScale
    return min(310, max(280, room))
  }
  /// Shortened, when a keyboard is up, so its buttons stay above it.
  var panelHeight: CGFloat {
    guard let keyboardTop else { return restingPanelHeight }
    let room = keyboardTop - 8 - Self.buttonHeight - 13 - panelTop
    return max(100, min(restingPanelHeight, room))
  }
  var isPanelCompact: Bool { panelHeight < restingPanelHeight - 0.5 && panelHeight < 280 }
  var buttonsTop: CGFloat { panelTop + panelHeight + 13 }
  var buttonsWidth: CGFloat { panelWidth - 16 }

  var captureCenterY: CGFloat { size.height / 2 - 0.26 }

  /// The scene's scale: the width's, unless the scene would then reach up
  /// into the capture button or the panel's buttons.
  var sceneScale: CGFloat {
    let belowCapture = (size.height / 2 - Self.captureHalfHeight - 12) / Self.sceneVisibleHeight
    let restingButtonsTop = panelTop + restingPanelHeight + 13
    let belowButtons = (size.height - restingButtonsTop - Self.buttonHeight - 12) / Self.sceneVisibleHeight
    return max(0.5, min(widthScale, belowCapture, belowButtons))
  }
}

/// The character at the bottom of the home, with his speech bubbles and the
/// price line, drawn in the design's own coordinates: a 402×337 box whose
/// bottom is the bottom of the screen. The caller scales and places it.
struct QuestionHomeScene: View {
  let mode: QuestionHomeMode
  let firstBubbleText: String
  let teacherCount: String
  let teacherLabel: String
  let priceText: String
  let footnote: String
  let footnoteColor: Color
  let textColor: Color
  /// The language's direction, for the text. The art is the same in both.
  let textDirection: LayoutDirection

  var body: some View {
    ZStack(alignment: .topLeading) {
      art("intro-character-shadow", x: 41.13, y: 270.11, width: 73.866, height: 9.613)
      art("intro-character-glow", x: 94, y: 97, width: 54, height: 54)
      art("home-character", x: -76, y: 0, width: 308, height: 308)

      firstBubble
        .offset(x: 107, y: 30)

      priceBubble
        .offset(x: 134.5, y: 110.5)

      SpeechBubble(
        lines: [teacherCount] + teacherLabel.components(separatedBy: "\n"),
        boldsFirstLine: true,
        textCenterX: 51,
        textTop: 37.5,
        textWidth: 70,
        textColor: textColor,
        textDirection: textDirection
      )
      .offset(x: 211.5, y: 30.5)

      Text(footnote)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(footnoteColor)
        .multilineTextAlignment(.center)
        .frame(width: 259)
        .readingDirection(textDirection)
        .offset(x: 98, y: 256)
    }
    .frame(width: QuestionHomeLayout.designWidth, height: QuestionHomeLayout.sceneHeight, alignment: .topLeading)
    .environment(\.layoutDirection, .leftToRight)
    .allowsHitTesting(false)
  }

  /// The camera's first bubble sets Hebrew flush right, as the design does;
  /// English, which would otherwise run into the bubble's left edge, is
  /// centred like the others.
  private var firstBubble: some View {
    let isFlushRight = mode == .photo && textDirection == .rightToLeft
    return SpeechBubble(
      lines: firstBubbleText.components(separatedBy: "\n"),
      textCenterX: isFlushRight ? 43 : 53,
      textTop: mode == .photo ? 42 : 39,
      textWidth: 92,
      alignment: isFlushRight ? .leading : .center,
      textColor: textColor,
      textDirection: textDirection
    )
  }

  /// One line as designed, centred where the design centres it; a longer
  /// translation broken over lines stays centred on the same point.
  private var priceBubble: some View {
    let lines = priceText.components(separatedBy: "\n")
    let lineHeight: CGFloat = 14.3
    return SpeechBubble(
      lines: lines,
      textCenterX: 51,
      textTop: 45.5 - CGFloat(lines.count - 1) * lineHeight / 2,
      textWidth: 70,
      fontSize: 13,
      weight: .bold,
      lineHeight: lines.count > 1 ? lineHeight : nil,
      textColor: textColor,
      textDirection: textDirection
    )
  }

  private func art(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
    Image(decorative: name, bundle: .module)
      .resizable()
      .frame(width: width, height: height)
      .offset(x: x, y: y)
  }
}

/// A speech bubble from the design's art, with a few short lines in it.
///
/// The lines are set one to a row, 0.9 of the type size apart as the design
/// sets them — closer than either platform sets a paragraph.
struct SpeechBubble: View {
  static let size = CGSize(width: 112, height: 124.556)

  let lines: [String]
  var boldsFirstLine = false
  /// The centre of the text, from the bubble's left edge.
  var textCenterX: CGFloat
  /// The top of the first line, from the bubble's top edge.
  var textTop: CGFloat
  var textWidth: CGFloat
  var fontSize: CGFloat = 14
  var weight: Font.Weight = .regular
  /// Nil for a single line set at its natural height.
  var lineHeight: CGFloat? = 12.6
  var alignment: HorizontalAlignment = .center
  let textColor: Color
  let textDirection: LayoutDirection
  /// The art turned over, its tail pointing down to the right: for a
  /// character who stands to the bubble's right. The text stays as it is.
  var mirrorsArt = false
  /// Sets a line wider than `textWidth` smaller rather than let it run over
  /// the bubble's edge: for copy written after the design, in any language.
  var shrinksToFit = false

  var body: some View {
    ZStack(alignment: .topLeading) {
      Image(decorative: "home-speech-bubble", bundle: .module)
        .resizable()
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(x: mirrorsArt ? -1 : 1, y: 1)

      VStack(alignment: alignment, spacing: 0) {
        ForEach(0..<lines.count, id: \.self) { index in
          line(lines[index], isBold: weight == .bold || (boldsFirstLine && index == 0))
        }
      }
      .frame(width: textWidth, alignment: alignment == .leading ? .leading : .center)
      .readingDirection(textDirection)
      .offset(x: textCenterX - textWidth / 2, y: textTop)
    }
    .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
  }

  @ViewBuilder
  private func line(_ text: String, isBold: Bool) -> some View {
    if let lineHeight {
      lineText(text, isBold: isBold)
        .frame(height: lineHeight)
    } else {
      lineText(text, isBold: isBold)
    }
  }

  @ViewBuilder
  private func lineText(_ text: String, isBold: Bool) -> some View {
    if shrinksToFit {
      Text(text)
        .font(.system(size: fontSize, weight: isBold ? .bold : .regular))
        .foregroundStyle(textColor)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: textWidth, alignment: alignment == .leading ? .leading : .center)
        // Its own height, not the row's: the rows are set closer than a line
        // is tall, and the scale factor would otherwise shrink every line to
        // fit one.
        .fixedSize(horizontal: false, vertical: true)
    } else {
      Text(text)
        .font(.system(size: fontSize, weight: isBold ? .bold : .regular))
        .foregroundStyle(textColor)
        .lineLimit(1)
        .fixedSize()
    }
  }
}

extension View {
  /// Sets the view in a language's direction, inside a left-to-right screen
  /// laid out by coordinates. Put an `offset` after this, never before:
  /// Compose mirrors an offset inside right-to-left layout, where SwiftUI
  /// does not, and this keeps the offset outside it.
  func readingDirection(_ direction: LayoutDirection) -> some View {
    ZStack {
      environment(\.layoutDirection, direction)
    }
  }
}

/// The dots on the writing panel: 2pt squares every 16pt, from `origin`.
struct DotGrid: Shape {
  var origin: CGPoint
  var spacing: CGFloat = 16
  var dotSize: CGFloat = 2

  func path(in rect: CGRect) -> Path {
    var path = Path()
    var y = origin.y
    while y + dotSize <= rect.maxY {
      var x = origin.x
      while x + dotSize <= rect.maxX {
        path.addRect(CGRect(x: x, y: y, width: dotSize, height: dotSize))
        x += spacing
      }
      y += spacing
    }
    return path
  }
}
