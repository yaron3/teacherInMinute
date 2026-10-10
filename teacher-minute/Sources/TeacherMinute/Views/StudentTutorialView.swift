//
//  StudentTutorialView.swift
//  teacher-minute
//
//  Instant Teacher's tutorial, a page at a time. Skip closes it from any
//  page; the last page closes it with Let's start, or for good with Don't
//  show me again. Pages slide like screens being pushed: Next and Back move
//  the whole page off one edge as the next comes in from the other, and a
//  swipe drags them under the finger.
//
//  A page about the app itself shows a screenshot of it, numbered markers on
//  the controls it describes, and under it the same numbers with what each
//  control does — written in the app's language rather than drawn into the
//  picture, where it would be too small to read.
//

import SwiftUI

struct StudentTutorialView: View {
  let viewModel: StudentTutorialViewModel
  /// The size the tutorial has to lay out in. The width is a page's, which
  /// the pages slide by; the height sets how large a screenshot can be drawn
  /// above its callouts.
  @State var availableSize: CGSize = .zero
  /// How far a swipe in progress has dragged the pages, in points.
  @State var dragOffset: CGFloat = 0

  @Environment(\.layoutDirection) var layoutDirection
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    ZStack {
      BrandScreenBackground(streaks: .subpage)

      VStack(spacing: 0) {
        topBar
          .padding(.top, 8)
          .padding(.horizontal, 24)
          .frame(maxWidth: 520)

        Spacer(minLength: 16)

        pager

        Spacer(minLength: 16)

        pageDots
          .padding(.bottom, 24)

        controls
          .padding(.bottom, 16)
          .padding(.horizontal, 24)
          .frame(maxWidth: 520)
      }
    }
    .onGeometryChange(for: CGSize.self, of: { $0.size }) { size in
      availableSize = size
    }
    .gesture(pageSwipe)
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    .trackScreen(AnalyticsScreen.studentTutorial)
    .onAppear { viewModel.appeared() }
  }

  var topBar: some View {
    HStack {
      Text(viewModel.pageCounterText)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(theme.brandMutedText)

      Spacer(minLength: 0)

      // The last page closes with its own button, so it has no Skip. The
      // bar keeps its height, so the page under it does not move.
      if viewModel.isLastPage {
        Color.clear
          .frame(width: 1, height: 44)
      } else {
        Button {
          viewModel.skip()
        } label: {
          Text(viewModel.skipLabel)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(theme.brandSecondaryText)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .tappableFrame()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("student_tutorial_skip")
      }
    }
  }

  /// The check box under Let's start, and its label, which toggles it too.
  var dontShowAgainRow: some View {
    HStack(spacing: 10) {
      BrandCheckbox(isOn: Binding(
        get: { viewModel.dontShowAgain },
        set: { viewModel.dontShowAgain = $0 }
      ))
      .accessibilityIdentifier("student_tutorial_hide")

      Button {
        viewModel.dontShowAgain.toggle()
      } label: {
        Text(viewModel.dontShowAgainLabel)
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(theme.brandSecondaryText)
          .frame(minHeight: 44)
          .tappableFrame()
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: Pager

  /// Every page, side by side as if on one long strip, with the current one
  /// on screen. Turning a page slides the strip by a screen's width, so the
  /// next page comes in from the edge as the current one leaves by the
  /// other, and a swipe drags the strip under the finger.
  ///
  /// Each page is placed by its own offset in a ZStack rather than laid out
  /// in a row wider than the screen, which Compose would squeeze to fit.
  /// The offsets are physical, so the strip is laid out left to right and
  /// each page gets the language's direction back.
  var pager: some View {
    ZStack {
      ForEach(0..<viewModel.pages.count, id: \.self) { index in
        pageContent(viewModel.pages[index])
          .padding(.horizontal, 24)
          .frame(maxWidth: 520)
          .frame(width: max(availableSize.width, 1))
          .environment(\.layoutDirection, layoutDirection)
          .offset(x: pageOffset(for: index))
          // Until the width is known every page sits at 0, on top of the
          // current one.
          .opacity(availableSize.width > 0 || index == viewModel.pageIndex ? 1 : 0)
          .accessibilityHidden(index != viewModel.pageIndex)
      }
    }
    .frame(maxWidth: .infinity)
    .environment(\.layoutDirection, .leftToRight)
  }

  /// Where page `index` stands: a screen's width per page away from the
  /// current one, toward the side the next page comes from — the right in
  /// English, the left in Hebrew — plus the swipe in progress.
  func pageOffset(for index: Int) -> CGFloat {
    let towardNext: CGFloat = layoutDirection == .rightToLeft ? -1 : 1
    return towardNext * CGFloat(index - viewModel.pageIndex) * availableSize.width + dragOffset
  }

  /// How the strip moves when a page turns, from a button or a swipe.
  var pageTurnAnimation: Animation { .easeOut(duration: 0.32) }

  func turnToNextPage() {
    withAnimation(pageTurnAnimation) {
      dragOffset = 0
      viewModel.next()
    }
  }

  func turnToPreviousPage() {
    withAnimation(pageTurnAnimation) {
      dragOffset = 0
      viewModel.back()
    }
  }

  @ViewBuilder
  func pageContent(_ page: StudentTutorialPage) -> some View {
    if case .screenshot(let name) = page.art {
      screenshotPage(page, screenshot: name)
    } else {
      illustratedPage(page)
    }
  }

  func illustratedPage(_ page: StudentTutorialPage) -> some View {
    VStack(spacing: 20) {
      // The picture gives way first on a short screen, so the copy and the
      // buttons always fit.
      art(page.art)
        .frame(minHeight: 120, maxHeight: 260)
        .padding(.bottom, 16)

      Text(page.title)
        .font(.system(size: 26, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      Text(page.body)
        .font(.system(size: 17, weight: .semibold))
        .foregroundStyle(theme.brandSecondaryText)
        .multilineTextAlignment(.center)
        .lineSpacing(3)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
  }

  @ViewBuilder
  func art(_ art: StudentTutorialPage.Art) -> some View {
    switch art {
    case .character(let name):
      Image(decorative: name, bundle: .module)
        .resizable()
        .scaledToFit()
        // The renders stand in a wide margin of their own; this brings the
        // figure up to the height of the icon pages' circle.
        .scaleEffect(1.3)
        // Art: the same in both languages.
        .environment(\.layoutDirection, .leftToRight)
    case .screenshot(let name):
      Image(decorative: name, bundle: .module)
        .resizable()
        .scaledToFit()
    case .icon(let name):
      Circle()
        .fill(theme.brandActionBackground.opacity(0.12))
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: 168, maxHeight: 168)
        .overlay {
          Circle()
            .stroke(theme.brandActionBackground, lineWidth: 2)
        }
        .overlay {
          Image(name, bundle: .module)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(theme.brandActionBackground)
            .frame(width: 76, height: 76)
        }
    }
  }

  // MARK: Screenshot pages

  func screenshotPage(_ page: StudentTutorialPage, screenshot: String) -> some View {
    VStack(spacing: 14) {
      Text(page.title)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)

      annotatedScreenshot(screenshot, callouts: page.callouts)
        .frame(height: screenshotHeight(calloutCount: page.callouts.count))

      calloutLegend(page.callouts)
    }
    .frame(maxWidth: .infinity)
  }

  /// As tall as the screen allows once the title, the callouts and the
  /// controls have their room. The room is the last page's controls — Let's
  /// start and the check box under it — whatever page this is: every page is
  /// laid out at once in the pager, so the tallest one sets its height on all
  /// of them, the last page included.
  func screenshotHeight(calloutCount: Int) -> CGFloat {
    let reserved = 310 + CGFloat(calloutCount) * 34
    return min(480, max(180, availableSize.height - reserved))
  }

  /// The screenshot in a device-like frame, with a numbered marker on each
  /// control a callout describes. The markers are placed on the picture's
  /// own coordinates, which do not turn around with the language.
  func annotatedScreenshot(_ name: String, callouts: [StudentTutorialPage.Callout]) -> some View {
    Image(decorative: name, bundle: .module)
      .resizable()
      .aspectRatio(contentMode: .fit)
      .overlay {
        GeometryReader { proxy in
          ForEach(0..<callouts.count, id: \.self) { index in
            calloutMarker(index + 1)
              .position(
                x: proxy.size.width * CGFloat(callouts[index].x),
                y: proxy.size.height * CGFloat(callouts[index].y)
              )
          }
        }
      }
      .clipShape(RoundedRectangle(cornerRadius: 18))
      .overlay {
        RoundedRectangle(cornerRadius: 18)
          .stroke(theme.brandControlBorder, lineWidth: 2)
      }
      .environment(\.layoutDirection, .leftToRight)
  }

  func calloutMarker(_ number: Int) -> some View {
    Text("\(number)")
      .font(.system(size: 14, weight: .heavy))
      .foregroundStyle(theme.onBrandAction)
      .frame(width: 26, height: 26)
      .background(theme.brandActionBackground)
      .clipShape(Circle())
      .overlay {
        Circle()
          .stroke(theme.onBrandAction, lineWidth: 2)
      }
  }

  func calloutLegend(_ callouts: [StudentTutorialPage.Callout]) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(0..<callouts.count, id: \.self) { index in
        HStack(alignment: .top, spacing: 10) {
          calloutMarker(index + 1)
          Text(callouts[index].text)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.brandSecondaryText)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        }
      }
    }
  }

  var pageDots: some View {
    HStack(spacing: 8) {
      ForEach(0..<viewModel.pages.count, id: \.self) { index in
        Capsule()
          .fill(index == viewModel.pageIndex ? theme.brandActionBackground : theme.brandControlBorder)
          .frame(width: index == viewModel.pageIndex ? 22 : 8, height: 8)
      }
    }
  }

  @ViewBuilder
  var controls: some View {
    if viewModel.isLastPage {
      VStack(spacing: 12) {
        BrandPrimaryButton(title: viewModel.startLabel) {
          viewModel.finish()
        }
        .accessibilityIdentifier("student_tutorial_start")

        dontShowAgainRow
      }
    } else {
      HStack(spacing: 12) {
        if !viewModel.isFirstPage {
          BrandSecondaryButton(title: viewModel.backLabel, height: 56) {
            turnToPreviousPage()
          }
          .accessibilityIdentifier("student_tutorial_back")
        }

        BrandPrimaryButton(title: viewModel.nextLabel) {
          turnToNextPage()
        }
        .accessibilityIdentifier("student_tutorial_next")
      }
    }
  }

  /// The strip follows a sideways swipe, holding back at either end, and
  /// on release turns the page when the swipe went far enough — a quarter of
  /// the screen — or springs back. Toward the start of the line is forward,
  /// as in a book in the language's direction.
  var pageSwipe: some Gesture {
    DragGesture(minimumDistance: 20)
      .onChanged { value in
        let distance = value.translation.width
        guard abs(distance) > abs(value.translation.height) else { return }
        dragOffset = isPastEnd(distance) ? distance / 3 : distance
      }
      .onEnded { value in
        let distance = value.translation.width
        let threshold = max(60, availableSize.width / 4)
        if abs(distance) > threshold, !isPastEnd(distance) {
          if isTowardNext(distance) {
            turnToNextPage()
          } else {
            turnToPreviousPage()
          }
        } else {
          withAnimation(pageTurnAnimation) { dragOffset = 0 }
        }
      }
  }

  func isTowardNext(_ distance: CGFloat) -> Bool {
    layoutDirection == .rightToLeft ? distance > 0 : distance < 0
  }

  /// A swipe back from the first page, or on from the last, has nowhere to go.
  func isPastEnd(_ distance: CGFloat) -> Bool {
    isTowardNext(distance) ? viewModel.isLastPage : viewModel.isFirstPage
  }
}

#if os(iOS)
struct StudentTutorialView_Previews: PreviewProvider {
  static var previews: some View {
    StudentTutorialView(viewModel: StudentTutorialViewModel(source: .menu) {})
  }
}
#endif
