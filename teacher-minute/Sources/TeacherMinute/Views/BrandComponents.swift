import SwiftUI

// The pieces the dark brand screens are built from: sign-up, the profile
// step, buying minutes and the purchase's confirmation.

/// The brand gradient, with a set of streaks across the bottom when asked.
struct BrandScreenBackground: View {
  var streaks: BrandStreaks.Arrangement?

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    ZStack {
      LinearGradient(
        colors: [theme.brandBackgroundTop, theme.brandBackgroundBottom],
        startPoint: .top,
        endPoint: .bottom
      )
      if let streaks {
        BrandStreaks(arrangement: streaks)
      }
    }
    .ignoresSafeArea()
  }
}

/// The square back button in a brand screen's header. Its arrow points the
/// way back in the language's direction: right in Hebrew, as designed.
struct BrandBackButton: View {
  let accessibilityLabel: String
  let action: () -> Void

  @Environment(\.layoutDirection) var layoutDirection
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button {
      action()
    } label: {
      Image("brand-back-arrow", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.brandActionBackground)
        .frame(width: 22, height: 22)
        .scaleEffect(x: layoutDirection == .rightToLeft ? 1 : -1, y: 1)
        .frame(width: 44, height: 44)
        .background(theme.brandActionBackground.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(theme.brandControlBorder, lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
#if !os(Android)
    // SkipUI has no string `accessibilityLabel`.
    .accessibilityLabel(accessibilityLabel)
#endif
    .accessibilityIdentifier("brand_back_button")
  }
}

/// The cyan call to action. Its label is 25pt, as designed, and smaller only
/// where a translation would not fit on one line at that size.
struct BrandPrimaryButton: View {
  let title: String
  var isLoading = false
  var isEnabled = true
  let action: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button {
      action()
    } label: {
      ZStack {
        ViewThatFits(in: .horizontal) {
          label(size: 25)
          label(size: 21)
          label(size: 17)
        }
        .opacity(isLoading ? 0 : 1)
        if isLoading {
          ProgressView()
            .tint(theme.onBrandAction)
        }
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
      .opacity(isEnabled ? 1 : 0.35)
    }
    .buttonStyle(.plain)
    .disabled(isLoading || !isEnabled)
  }

  private func label(size: CGFloat) -> some View {
    Text(title)
      .font(.system(size: size, weight: .bold))
      .foregroundStyle(theme.onBrandAction)
      .lineLimit(1)
      .fixedSize()
  }
}

/// A labelled text field: the label above, unless it is empty, then a dark
/// field with an icon at its leading end when there is one, and the error
/// under it while the value is not valid.
struct BrandTextField: View {
  let title: String
  let placeholder: String
  @Binding var text: String
  var icon: String?
  var isSecure = false
  var isValid = true
  var errorMessage = ""
  var keyboardType: UIKeyboardType = .default
  var textContentType: UITextContentType?
  var autocapitalization: TextInputAutocapitalization = .sentences

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !title.isEmpty {
        Text(title)
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(theme.brandSecondaryText)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      HStack(spacing: 8) {
        if let icon {
          Image(icon, bundle: .module)
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(theme.onDarkFill)
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
        }
        field
      }
      .padding(.horizontal, 12)
      .frame(height: 52)
      .background(theme.brandBackgroundTop)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(isValid ? theme.brandControlBorder : theme.danger, lineWidth: 1)
      }

      if !isValid {
        Text(errorMessage)
          .font(.system(size: 12))
          .foregroundStyle(theme.danger)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  @ViewBuilder
  private var field: some View {
    if isSecure {
      SecureField("", text: $text, prompt: prompt)
        .font(.system(size: 16))
        .foregroundStyle(theme.onDarkFill)
        .tint(theme.brandActionBackground)
        .textFieldStyle(.plain)
    } else {
      TextField("", text: $text, prompt: prompt)
        .font(.system(size: 16))
        .foregroundStyle(theme.onDarkFill)
        .tint(theme.brandActionBackground)
        .textFieldStyle(.plain)
        .keyboardType(keyboardType)
        .textContentType(textContentType)
        .textInputAutocapitalization(autocapitalization)
    }
  }

  private var prompt: Text {
    Text(placeholder).foregroundColor(theme.brandSecondaryText)
  }
}

/// A square check box that fills with a cyan tick when on.
struct BrandCheckbox: View {
  @Binding var isOn: Bool

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      ZStack {
        RoundedRectangle(cornerRadius: 6)
          .fill(theme.brandCardSurface)
        RoundedRectangle(cornerRadius: 6)
          .stroke(theme.brandControlBorder, lineWidth: 1)
        if isOn {
          Image("brand-check", bundle: .module)
            .renderingMode(.template)
            .resizable()
            .foregroundStyle(theme.brandActionBackground)
            .frame(width: 12, height: 12)
        }
      }
      .frame(width: 20, height: 20)
      .tappableFrame()
    }
    .buttonStyle(.plain)
  }
}

/// The brand's modal card, as the "not enough minutes" prompt draws it: dark,
/// outlined, 354pt wide or the screen less its 24pt margins, centred over
/// the dimmed screen.
struct BrandModal<Content: View>: View {
  let content: Content

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        theme.brandScrim.opacity(0.7)

        VStack(spacing: 18) {
          content
        }
        .padding(24)
        // An explicit width: a maximum one lets the card's background spread
        // across the screen on Android.
        .frame(width: min(354, proxy.size.width - 48))
        .background(theme.brandModalBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay {
          RoundedRectangle(cornerRadius: 20)
            .stroke(theme.brandControlBorder, lineWidth: 1)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    // The container's safe area, not the keyboard's: a modal with a field is
    // centred above the keyboard, where its buttons can still be reached.
    .ignoresSafeArea(.container)
  }
}

/// A modal's title and message, centred.
struct BrandModalText: View {
  let title: String
  var message: String?

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    VStack(spacing: 8) {
      Text(title)
        .font(.system(size: 22, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)

      if let message, !message.isEmpty {
        Text(message)
          .font(.system(size: 15))
          .foregroundStyle(theme.brandSecondaryText)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity)
      }
    }
    .multilineTextAlignment(.center)
  }
}

/// The round badge at the top of a modal, as the prompt's timer: a symbol
/// on the brand's cyan tint.
struct BrandModalBadge: View {
  let systemName: String

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    PlatformIcon(systemName: systemName, size: 24, color: theme.brandActionBackground)
      .frame(width: 56, height: 56)
      .background(theme.brandActionBackground.opacity(0.12))
      .clipShape(Circle())
      .accessibilityHidden(true)
  }
}

/// The secondary choice beside a `BrandPrimaryButton`: outlined in cyan.
struct BrandSecondaryButton: View {
  let title: String
  /// 56 where it stands under a primary button in a modal, as the design
  /// draws it there.
  var height: CGFloat = 52
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
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(theme.brandActionBackground)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .stroke(theme.brandActionBackground, lineWidth: 1)
        }
        .tappableFrame()
    }
    .buttonStyle(.plain)
  }
}

extension View {
  /// The ground a full screen stands on: the brand's gradient.
  func screenGround() -> some View {
    background {
      BrandScreenBackground()
    }
  }

  /// The translucent card a brand screen's form sits in.
  func brandCard(cornerRadius: CGFloat = 16, padding: CGFloat = 16) -> some View {
    modifier(BrandCardModifier(cornerRadius: cornerRadius, padding: padding))
  }

  /// Lets a drag down a form put the keyboard away — on iOS only.
  ///
  /// SkipUI cannot tell a finger's drag from Compose's own scroll that brings a
  /// newly focused field above the keyboard, so on Android it closed the
  /// keyboard, and cleared focus, the moment a field low on the form was
  /// tapped: the login password could not be typed into at all.
  @ViewBuilder
  func formScrollDismissesKeyboard() -> some View {
#if os(Android)
    self
#else
    scrollDismissesKeyboard(.interactively)
#endif
  }
}

struct BrandCardModifier: ViewModifier {
  let cornerRadius: CGFloat
  let padding: CGFloat

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .background(theme.brandCardSurface)
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .overlay {
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(theme.brandControlBorder, lineWidth: 1)
      }
  }
}
