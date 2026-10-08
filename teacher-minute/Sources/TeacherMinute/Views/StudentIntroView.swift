import SwiftUI

/// The first screen of Instant Teacher for a student who is not signed in:
/// what the app does, and one button that starts them without an account.
struct StudentIntroView: View {
  @State var viewModel = StudentIntroViewModel()
  /// The card's height as laid out: longer copy, as in English, makes it
  /// taller than the design's 374pt, and the character stands below it.
  @State var cardHeight: CGFloat = 374
  @Environment(\.appRouter) var router

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    ZStack(alignment: .top) {
      LinearGradient(
        colors: [theme.brandBackgroundTop, theme.brandBackgroundBottom],
        startPoint: .top,
        endPoint: .bottom
      )
      .ignoresSafeArea()

      BrandStreaks()
        .ignoresSafeArea()

      card
        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { height in
          cardHeight = height
        }
        .padding(.top, 40)

      // The character stands in front of the card, the top of his head over
      // its bottom edge. He is moved there rather than laid out there: his
      // square runs off the screen, and Compose would centre a view that does
      // not fit where SwiftUI lets it hang over the edge.
      character
        .offset(y: 40 + cardHeight - 116)
    }
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    .trackScreen(AnalyticsScreen.studentIntro)
    .onChange(of: viewModel.destination) { _, destination in
      guard let destination else { return }
      router.resume(destination)
    }
    .appDialog(
      viewModel.startErrorTitle,
      isPresented: Binding(
        get: { viewModel.startErrorMessage != nil },
        set: { if !$0 { viewModel.startErrorMessage = nil } }
      ),
      message: viewModel.startErrorMessage,
      actions: [AppDialogAction(viewModel.okLabel)]
    )
    .otherAppAccountNotice()
  }

  private var card: some View {
    VStack(spacing: 0) {
      Text(viewModel.stuckQuestion)
        .foregroundStyle(theme.onDarkFill)
        .frame(minHeight: 31)
        .padding(.top, 47)

      // As on the splash: one line when it fits, and in English, which runs
      // longer, a break after the highlighted phrase.
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

      Text(viewModel.pitch)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.brandSecondaryText)
        .multilineTextAlignment(.leading)
        .lineSpacing(pitchLineSpacing)
        .padding(.vertical, pitchLineSpacing / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 58)
        .padding(.trailing, 31)
        .padding(.top, 12)
	  
      if let promotion = viewModel.promotionText {
        Text(promotion)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(theme.brandHighlightText)
          .multilineTextAlignment(.leading)
          .lineSpacing(pitchLineSpacing)
          .padding(.vertical, pitchLineSpacing / 2)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.leading, 58)
          .padding(.trailing, 31)
          .padding(.top, 12)
      }
	  
      startButton
        .padding(.top, 28)

      Text(viewModel.priceLine)
        .font(.system(size: 13, weight: .bold))
        .foregroundStyle(theme.brandMutedText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 71)
    }
    .font(.system(size: 25, weight: .bold))
    .multilineTextAlignment(.center)
    .frame(width: 327)
    .frame(minHeight: 374, alignment: .top)
    .overlay {
      RoundedRectangle(cornerRadius: 8)
        .stroke(theme.brandCardBorder, lineWidth: 1)
    }
  }

  /// What brings the pitch's lines out to the design's Noto Sans Hebrew line
  /// height. iOS sets it in SF, whose 15pt lines are 2.5pt shorter; Android's
  /// Hebrew face is Noto itself.
  private var pitchLineSpacing: CGFloat {
#if os(Android)
    0
#else
    2.5
#endif
  }

  private var humanTeacherHighlight: some View {
    headlineLine(viewModel.humanTeacherHighlight, color: theme.brandHighlightText)
  }

  private var responseTimePromise: some View {
    headlineLine(viewModel.responseTimePromise, color: theme.onDarkFill)
  }

  /// A line of the headline, as tall as a line of the design's Noto Sans Hebrew.
  private func headlineLine(_ text: String, color: Color) -> some View {
    Text(text)
      .foregroundStyle(color)
      .frame(minHeight: 34)
  }

  private var startButton: some View {
    Button {
      Task { await viewModel.start() }
    } label: {
      ZStack {
        // The label keeps the button its size while the spinner stands in.
        Text(viewModel.startLabel)
          .opacity(viewModel.isStarting ? 0 : 1)
        if viewModel.isStarting {
          ProgressView()
            .tint(theme.onBrandAction)
        }
      }
      .font(.system(size: 25, weight: .bold))
      .foregroundStyle(theme.onBrandAction)
      .padding(.horizontal, 49)
      .frame(minHeight: 54)
      .background(theme.brandActionBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(theme.onBrandAction, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isStarting)
  }

  /// The character, with the cyan glow behind his stopwatch and his shadow,
  /// placed as the design places them in its 497pt square.
  private var character: some View {
    ZStack(alignment: .topLeading) {
      Image(decorative: "intro-character-shadow", bundle: .module)
        .resizable()
        .frame(width: 146, height: 19)
        .offset(x: 180, y: 437)

      Image(decorative: "intro-character-glow", bundle: .module)
        .resizable()
        .frame(width: 106.73, height: 106.73)
        .offset(x: 104.39, y: 163.02)

      Image(decorative: "intro-character", bundle: .module)
        .resizable()
        .frame(width: 497, height: 497)
    }
    .frame(width: 497, height: 497, alignment: .topLeading)
    // Art: the same in both languages.
    .environment(\.layoutDirection, .leftToRight)
    .allowsHitTesting(false)
  }
}

#if os(iOS)
struct StudentIntroView_Previews: PreviewProvider {
  static var previews: some View {
    StudentIntroView()
  }
}
#endif
