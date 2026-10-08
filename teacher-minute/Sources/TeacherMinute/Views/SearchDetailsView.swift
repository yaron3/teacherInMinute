//
//  SearchDetailsView.swift
//  teacher-minute
//
//  What a student sees while their question is offered to teachers: three
//  short questions that sharpen it — what it is about, why they are stuck, how
//  they would like to start — each going out to the teachers as it is
//  answered, and then something to smile at while they wait.
//

import SwiftUI

/// Where the search's screens put things, worked out from the screen.
///
/// The design is drawn on a 402×874 screen. Its card keeps its size and its
/// distance below the status bar. The character's scene keeps its place at
/// the bottom of the screen and scales with the width, and shrinks further
/// rather than reach up into the card's button. The waiting card runs down to
/// 100pt above the bottom, as designed, and its drawings scale with it.
struct SearchDetailsLayout {
  let size: CGSize
  /// The status bar's height, which the card sits under.
  let safeTop: CGFloat

  static let designWidth: CGFloat = 402
  static let designHeight: CGFloat = 874
  static let questionCardHeight: CGFloat = 374
  /// The waiting card as designed, the height its drawings are drawn for.
  static let designWaitingCardHeight: CGFloat = 672
  /// The waiting card's drawings: as wide as the card, and down to the
  /// teacher's shadow, which stands below it.
  static let waitingSceneSize = CGSize(width: 327, height: 707)
  /// The character's scene: from the left of his image to its right, and
  /// from its top to the bottom of the screen.
  static let sceneSize = CGSize(width: 497, height: 514)
  /// Where the scene's box starts in the design's frame.
  static let sceneOrigin = CGPoint(x: -47, y: 360)
  /// From the top of the bubble's art to the bottom of the screen.
  static let sceneVisibleHeight: CGFloat = 437.5

  var widthScale: CGFloat { size.width / Self.designWidth }
  var centerX: CGFloat { size.width / 2 }

  var cardWidth: CGFloat { min(327, size.width - 32) }
  var cardLeading: CGFloat { (size.width - cardWidth) / 2 }
  var cardTop: CGFloat { safeTop + 55 }
  var titleTop: CGFloat { cardTop + 38 }
  var buttonTop: CGFloat { cardTop + 271 }
  var closeTop: CGFloat { safeTop + 4 }

  /// The prompt's top, where the design puts each screen's: the subject's
  /// highest, the start's, with one row of choices, lowest.
  func promptTop(_ step: SearchDetailsStep) -> CGFloat {
    switch step {
    case .topic: return cardTop + 93
    case .struggle: return cardTop + 98.5
    case .start, .waiting: return cardTop + 136.5
    }
  }

  /// From the prompt's top to its choices'.
  func promptHeight(_ step: SearchDetailsStep) -> CGFloat {
    step == .topic ? 47 : 36
  }

  var choicesWidth: CGFloat { cardWidth - 52 }

  /// The choices' left edge. They keep the design's distance from the card's
  /// edge on the side they start from: the right, in Hebrew.
  func choicesLeading(_ step: SearchDetailsStep, direction: LayoutDirection) -> CGFloat {
    let inset: CGFloat = step == .topic ? 22 : 25
    return direction == .rightToLeft
      ? cardLeading + cardWidth - inset - choicesWidth
      : cardLeading + inset
  }

  /// The width's scale, unless the bubble would then reach up to the button.
  var sceneScale: CGFloat {
    let room = (size.height - (buttonTop + 56 + 7)) / Self.sceneVisibleHeight
    return max(0.5, min(widthScale, room))
  }

  /// The scene's centre. Both platforms centre a view that overflows its
  /// frame on it, so the scene hangs from this point.
  var sceneCenter: CGPoint {
    let leading = (size.width - Self.designWidth * sceneScale) / 2
    return CGPoint(
      x: leading + (Self.sceneOrigin.x + Self.sceneSize.width / 2) * sceneScale,
      y: size.height - Self.sceneSize.height / 2 * sceneScale
    )
  }

  var waitingCardHeight: CGFloat { max(360, size.height - cardTop - 100) }
  var waitingScale: CGFloat { min(widthScale, waitingCardHeight / Self.designWaitingCardHeight) }
  var waitingSceneCenter: CGPoint {
    CGPoint(x: centerX, y: cardTop + Self.waitingSceneSize.height / 2 * waitingScale)
  }

  /// The dots that say the search is still going, in the waiting card's
  /// bottom right, clear of the teacher, who stands on the left. On the right
  /// in Hebrew too: the art is not mirrored, so neither is the space it
  /// leaves.
  static let waitingDotsSize = CGSize(width: 60, height: 20)
  var waitingDotsOrigin: CGPoint {
    CGPoint(
      x: cardLeading + cardWidth - 20 - Self.waitingDotsSize.width,
      y: cardTop + waitingCardHeight - 20 - Self.waitingDotsSize.height
    )
  }
}

/// Replaces the search's old spinner. Shown for as long as the question is
/// being offered: a teacher who accepts ends it, at any step.
struct SearchDetailsView: View {
  let viewModel: any StudentHomeViewModeling
  let onCancel: () -> Void

  @Environment(\.layoutDirection) var layoutDirection
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    GeometryReader { proxy in
      let insets = proxy.safeAreaInsets
      let layout = SearchDetailsLayout(
        size: CGSize(
          width: proxy.size.width + insets.leading + insets.trailing,
          height: proxy.size.height + insets.top + insets.bottom
        ),
        safeTop: insets.top
      )
      ZStack(alignment: .topLeading) {
        BrandScreenBackground(streaks: .home)
        if step == .waiting {
          waitingCard(layout)
        } else {
          questionCard(layout)
          scene(layout)
        }
        closeButton(layout)
      }
      .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
      // Placed by offsets, which Compose would mirror in right-to-left. The
      // text is set in the language's direction where it is drawn.
      .environment(\.layoutDirection, .leftToRight)
      .ignoresSafeArea()
    }
    .overlay {
      if viewModel.searchDetails.pendingStart != nil {
        SearchPermissionPrompt(viewModel: viewModel)
      }
    }
    .appDialog(
      viewModel.permissionRequiredTitle,
      isPresented: Binding(
        get: { viewModel.searchDetails.startDeniedMessage != nil },
        set: { if !$0 { viewModel.dismissSearchStartDenied() } }
      ),
      message: viewModel.searchDetails.startDeniedMessage,
      actions: [
        AppDialogAction(viewModel.openSettingsLabel) {
          viewModel.openSearchPermissionSettings()
        },
        AppDialogAction(viewModel.okLabel, kind: .cancel),
      ]
    )
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
  }

  // MARK: - The questions

  func questionCard(_ layout: SearchDetailsLayout) -> some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 8)
        .stroke(theme.brandCardBorder, lineWidth: 1)
        .frame(width: layout.cardWidth, height: SearchDetailsLayout.questionCardHeight)
        .offset(x: layout.cardLeading, y: layout.cardTop)

      Text(viewModel.searchDetailsTitle)
        .font(.system(size: 25, weight: .bold))
        .foregroundStyle(theme.brandHighlightText)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: layout.cardWidth - 32, height: 34)
        .readingDirection(layoutDirection)
        .offset(x: layout.cardLeading + 16, y: layout.titleTop)

      choices(promptHeight: layout.promptHeight(step))
        .frame(width: layout.choicesWidth, alignment: .topLeading)
        .readingDirection(layoutDirection)
        .offset(
          x: layout.choicesLeading(step, direction: layoutDirection),
          y: layout.promptTop(step)
        )

      BrandPrimaryButton(title: viewModel.searchNextLabel) {
        viewModel.advanceSearchDetails()
      }
      .frame(width: 164)
      .accessibilityIdentifier("search_details_next")
      .offset(x: layout.centerX - 82, y: layout.buttonTop)
    }
  }

  var step: SearchDetailsStep {
    viewModel.searchDetails.step
  }

  func choices(promptHeight: CGFloat) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(viewModel.searchDetailsPrompt)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.brandSecondaryText)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: promptHeight, alignment: .top)

      choiceRows
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  var choiceRows: some View {
    switch step {
    case .topic:
      chipRows(
        viewModel.searchTopicRows,
        title: { viewModel.searchTopicLabel($0) },
        isChosen: { viewModel.isSearchTopicChosen($0) },
        choose: { viewModel.chooseSearchTopic($0) }
      )
    case .struggle:
      chipRows(
        viewModel.searchStruggleRows,
        title: { viewModel.searchStruggleLabel($0) },
        isChosen: { viewModel.isSearchStruggleChosen($0) },
        choose: { viewModel.chooseSearchStruggle($0) }
      )
    case .start, .waiting:
      chipRows(
        viewModel.searchStartRows,
        title: { viewModel.searchStartLabel($0) },
        isChosen: { viewModel.isSearchStartChosen($0) },
        choose: { viewModel.chooseSearchStart($0) }
      )
    }
  }

  /// The choices in the design's rows: SkipUI has no flow layout to wrap
  /// them itself.
  func chipRows(
    _ rows: [[String]],
    title: @escaping (String) -> String,
    isChosen: @escaping (String) -> Bool,
    choose: @escaping (String) -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(0..<rows.count, id: \.self) { index in
        HStack(spacing: 8) {
          ForEach(rows[index], id: \.self) { key in
            SearchChoiceChip(title: title(key), isChosen: isChosen(key)) {
              choose(key)
            }
            .accessibilityIdentifier("search_choice_\(key)")
          }
        }
      }
    }
  }

  /// The character at the bottom, with what the search is doing in his
  /// bubble.
  func scene(_ layout: SearchDetailsLayout) -> some View {
    SearchCharacterScene(
      bubbleLines: viewModel.searchBubbleLines,
      textColor: theme.onBrandAction,
      textDirection: layoutDirection
    )
    .scaleEffect(layout.sceneScale)
    .frame(width: 0, height: 0)
    .offset(x: layout.sceneCenter.x, y: layout.sceneCenter.y)
  }

  // MARK: - The wait

  func waitingCard(_ layout: SearchDetailsLayout) -> some View {
    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: 8)
        .stroke(theme.brandCardBorder, lineWidth: 1)
        .frame(width: layout.cardWidth, height: layout.waitingCardHeight)
        .offset(x: layout.cardLeading, y: layout.cardTop)

      SearchWaitingScene(
        joke: viewModel.searchWaitingJoke,
        textColor: theme.onDarkFill,
        textDirection: layoutDirection
      )
      .scaleEffect(layout.waitingScale)
      .frame(width: 0, height: 0)
      .offset(x: layout.waitingSceneCenter.x, y: layout.waitingSceneCenter.y)

      LottieLoopView(name: "search-waiting-dots")
        .frame(
          width: SearchDetailsLayout.waitingDotsSize.width,
          height: SearchDetailsLayout.waitingDotsSize.height
        )
        .offset(x: layout.waitingDotsOrigin.x, y: layout.waitingDotsOrigin.y)
    }
  }

  /// Not in the design, which leaves the student no way out of the search:
  /// the brand sheet's close button, over the card's far corner.
  func closeButton(_ layout: SearchDetailsLayout) -> some View {
    BrandCloseButton(accessibilityLabel: viewModel.cancelLabel) {
      onCancel()
    }
    .accessibilityIdentifier("search_details_cancel")
    .offset(
      x: layoutDirection == .rightToLeft ? layout.cardLeading : layout.cardLeading + layout.cardWidth - 44,
      y: layout.closeTop
    )
  }
}

/// A choice on the search's screens: violet, or cyan once chosen.
struct SearchChoiceChip: View {
  let title: String
  let isChosen: Bool
  let action: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button {
      action()
    } label: {
      Text(title)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(isChosen ? theme.onBrandAction : theme.onDarkFill)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(isChosen ? theme.brandActionBackground : theme.brandControlBorder)
        .clipShape(Capsule())
        .overlay {
          Capsule()
            .stroke(theme.brandControlBorder, lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .accessibilitySelected(isChosen)
  }
}

/// The character under the card, his stopwatch aglow, and his bubble, in the
/// design's own coordinates: a 497×514 box from the left of his image, whose
/// bottom is the bottom of the screen. The caller scales and places it.
struct SearchCharacterScene: View {
  let bubbleLines: [String]
  let textColor: Color
  /// The language's direction, for the text. The art is the same in both.
  let textDirection: LayoutDirection

  var body: some View {
    ZStack(alignment: .topLeading) {
      art("intro-character-shadow", x: 180, y: 437, width: 146, height: 19)
      art("intro-character-glow", x: 104.39, y: 163.02, width: 106.734, height: 106.734)
      art("search-character", x: 0, y: 0, width: 497, height: 497)

      SpeechBubble(
        lines: bubbleLines,
        textCenterX: 60.5,
        textTop: 36.5,
        // As wide as the bubble is inside where its last line falls, less
        // a margin.
        textWidth: 72,
        textColor: textColor,
        textDirection: textDirection,
        mirrorsArt: true,
        shrinksToFit: true,
        animationAbove: "search-bubble-dots"
      )
      .offset(x: 82, y: 59.5)
    }
    .frame(
      width: SearchDetailsLayout.sceneSize.width,
      height: SearchDetailsLayout.sceneSize.height,
      alignment: .topLeading
    )
    .environment(\.layoutDirection, .leftToRight)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func art(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
    Image(decorative: name, bundle: .module)
      .resizable()
      .frame(width: width, height: height)
      .offset(x: x, y: y)
  }
}

/// The wait, in the design's coordinates from the card's top left: the joke,
/// the boy stuck on his sums on a ledge, and the teacher on his way, who
/// stands over the card's bottom edge. The caller scales and places it.
struct SearchWaitingScene: View {
  let joke: String
  let textColor: Color
  let textDirection: LayoutDirection

  var body: some View {
    ZStack(alignment: .topLeading) {
      Text(joke)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(textColor)
        .multilineTextAlignment(.center)
        .designLineHeight(fontSize: 20)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 213)
        .readingDirection(textDirection)
        .offset(x: 60, y: 88)

      art("intro-character-shadow", x: 26, y: 697, width: 73.866, height: 9.613)
      art("search-wait-teacher", x: -93, y: 435, width: 300, height: 300)
      art("search-wait-line", x: 72, y: 356, width: 162, height: 1)
      art("intro-character-shadow", x: 137, y: 342, width: 64, height: 21)
      art("search-wait-boy", x: 85.563, y: 236.568, width: 135.131, height: 207.89)
    }
    .frame(
      width: SearchDetailsLayout.waitingSceneSize.width,
      height: SearchDetailsLayout.waitingSceneSize.height,
      alignment: .topLeading
    )
    .environment(\.layoutDirection, .leftToRight)
    .allowsHitTesting(false)
  }

  private func art(_ name: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> some View {
    Image(decorative: name, bundle: .module)
      .resizable()
      .frame(width: width, height: height)
      .offset(x: x, y: y)
      .accessibilityHidden(true)
  }
}

/// What a start needs before it can be taken — the microphone for audio, the
/// camera too for video — drawn as the "not enough minutes" prompt is.
struct SearchPermissionPrompt: View {
  let viewModel: any StudentHomeViewModeling

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        theme.brandScrim
          .onTapGesture { viewModel.declineSearchStartPermission() }

        // The design's 354pt, less where the screen is narrower than its
        // 24pt margins allow.
        card(width: min(354, proxy.size.width - 48))
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    // Centred on the whole screen, as the design has it.
    .ignoresSafeArea()
  }

  private func card(width: CGFloat) -> some View {
    VStack(spacing: 18) {
      badge

      Text(viewModel.searchPermissionTitle)
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 30)

      VStack(spacing: 10) {
        BrandPrimaryButton(title: viewModel.checkPermissionLabel) {
          Task { await viewModel.checkSearchStartPermission() }
        }
        .accessibilityIdentifier("search_permission_check")

        if viewModel.searchPermissionIsVideo {
          BrandSecondaryButton(title: viewModel.notNowLabel, height: 56) {
            viewModel.declineSearchStartPermission()
          }
          .accessibilityIdentifier("search_permission_not_now")
        }
      }
    }
    .padding(24)
    .frame(width: width)
    .background(theme.brandModalBackground)
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .overlay {
      RoundedRectangle(cornerRadius: 20)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
    .shadow(color: Color.black.opacity(0.4), radius: 24, x: 0, y: 18)
  }

  /// The microphone, or the camera, on the brand's cyan tint.
  private var badge: some View {
    let isVideo = viewModel.searchPermissionIsVideo
    return Image(isVideo ? "search-video" : "search-mic", bundle: .module)
      .renderingMode(.template)
      .resizable()
      .foregroundStyle(theme.onDarkFill)
      .frame(width: isVideo ? 24 : 14, height: isVideo ? 24 : 22)
      .frame(width: 56, height: 56)
      .background(theme.brandActionBackground.opacity(0.12))
      .clipShape(Circle())
      .accessibilityHidden(true)
  }
}

#if os(iOS)
struct SearchDetailsView_Previews: PreviewProvider {
  static var previews: some View {
    SearchDetailsView(
      viewModel: MockStudentHomeViewModel(searchState: .searching(questionId: "preview")),
      onCancel: {}
    )
  }
}
#endif
