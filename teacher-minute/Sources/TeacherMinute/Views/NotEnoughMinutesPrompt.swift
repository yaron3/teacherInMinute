import SwiftUI

/// Stands in front of the student's home when a question cannot go out for
/// want of minutes. A student who started without an account is offered one,
/// and the free minutes it earns; anyone else, the packages.
struct NotEnoughMinutesPrompt: View {
  let viewModel: any StudentHomeViewModeling
  /// Replaces the usual message, when the prompt stands in for something
  /// other than a question that cannot go out.
  var message: String?
  /// Create an account, or buy minutes: whichever the prompt offers.
  let onPrimary: () -> Void
  /// Log in to an existing account; offered only to a student without one.
  let onLogIn: () -> Void
  let onDismiss: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        theme.brandScrim
          .onTapGesture { onDismiss() }

        // The design's 354pt, less where the screen is narrower than its
        // 24pt margins allow.
        card(width: min(354, proxy.size.width - 48))
          // Where the design centres it, a little above the screen's middle.
          .offset(y: -10)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    // Centred on the whole screen, as the design has it, not on its safe area.
    .ignoresSafeArea()
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    .onAppear {
      viewModel.logNotEnoughMinutesShown()
    }
  }

  private func card(width: CGFloat) -> some View {
    VStack(spacing: 18) {
      timerBadge

      VStack(spacing: 8) {
        // Lines as tall as the design sets them: 30pt for the title, 22pt
        // for the message, 23pt for the balance.
        Text(viewModel.notEnoughMinutesTitle)
          .font(.system(size: 24, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .frame(maxWidth: .infinity, minHeight: 30)

        Text(message ?? viewModel.notEnoughMinutesMessage)
          .font(.system(size: 15))
          .foregroundStyle(theme.brandSecondaryText)
          .lineSpacing(messageLineSpacing)
          .padding(.vertical, messageLineSpacing / 2)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity)
      }
      .multilineTextAlignment(.center)

      balanceRow

      VStack(spacing: 10) {
        primaryButton
        if viewModel.isAnonymousAccount {
          logInButton
        }
        dismissButton
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

  /// Brings the message's lines to the design's 22pt: iOS sets it in SF,
  /// Android's Hebrew face is the design's Noto Sans Hebrew, whose lines are
  /// already taller.
  private var messageLineSpacing: CGFloat {
#if os(Android)
    1.6
#else
    4.1
#endif
  }

  private var timerBadge: some View {
    Image("minutes-timer", bundle: .module)
      .renderingMode(.template)
      .resizable()
      .foregroundStyle(theme.onDarkFill)
      .frame(width: 24, height: 24)
      .frame(width: 56, height: 56)
      .background(theme.brandActionBackground.opacity(0.12))
      .clipShape(Circle())
      .accessibilityHidden(true)
  }

  private var balanceRow: some View {
    HStack(spacing: 8) {
      Text(viewModel.currentBalanceLabel)
        .font(.system(size: 14))
        .foregroundStyle(theme.brandSecondaryText)
        .lineLimit(1)
      Spacer(minLength: 0)
      Text(viewModel.currentBalanceText)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(theme.brandActionBackground)
        .lineLimit(1)
    }
    .frame(minHeight: 23)
    .padding(.horizontal, 16)
    .padding(.vertical, 13)
    .background(theme.brandModalInset)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay {
      RoundedRectangle(cornerRadius: 14)
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
  }

  private var primaryButton: some View {
    Button {
      onPrimary()
    } label: {
      // 25pt as designed, smaller only where a translation would not fit.
      ViewThatFits(in: .horizontal) {
        primaryLabel(size: 25)
        primaryLabel(size: 21)
        primaryLabel(size: 17)
      }
      .padding(.horizontal, 12)
      .frame(maxWidth: .infinity)
      .frame(height: 56)
      .background(theme.brandActionBackground)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay {
        RoundedRectangle(cornerRadius: 8)
          .stroke(theme.onBrandAction, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("not_enough_minutes_primary")
  }

  private func primaryLabel(size: CGFloat) -> some View {
    Text(viewModel.notEnoughMinutesPrimaryLabel)
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(theme.brandBackgroundTop)
      .lineLimit(1)
      .fixedSize()
  }

  private var logInButton: some View {
    Button {
      onLogIn()
    } label: {
      Text(viewModel.alreadyHaveAccountLabel)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(theme.brandActionBackground)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .tappableFrame()
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(theme.brandActionBackground, lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("not_enough_minutes_log_in")
  }

  private var dismissButton: some View {
    Button {
      onDismiss()
    } label: {
      Text(viewModel.notNowLabel)
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(theme.brandActionBackground)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .tappableFrame()
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(theme.brandActionBackground, lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("not_enough_minutes_dismiss")
  }
}

#if os(iOS)
struct NotEnoughMinutesPrompt_Previews: PreviewProvider {
  static var previews: some View {
    NotEnoughMinutesPrompt(viewModel: MockStudentHomeViewModel(), onPrimary: {}, onLogIn: {}, onDismiss: {})
  }
}
#endif
