//
//  WelcomeView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 05/05/2026.
//
//  Pro Teacher's first screen for a teacher who is not signed in, on the
//  brand's ground: what the app is, and the ways to sign up or log in.
//

import SwiftUI

struct WelcomeView: View {
  @State var viewModel = WelcomeViewModel()
  @Environment(\.appRouter) var router

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    ZStack {
      BrandScreenBackground(streaks: .home)

      welcomeContent
    }
    .environment(\.colorScheme, .dark)
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
    .trackScreen(AnalyticsScreen.welcome)
    .otherAppAccountNotice()
  }

  private var welcomeContent: some View {
    GeometryReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          header

          Text(viewModel.headline)
            .font(.system(size: 35, weight: .bold))
            .foregroundStyle(theme.onDarkFill)
            .padding(.top, 24)
		  // Sized at most as designed, and smaller where the padded column is
		  // narrower: a fixed width wider than the column made the whole column
		  // wider than the screen, and the scroll view then pinned it to one
		  // edge instead of centring it.
		  ZStack(alignment: .top) {
			Image(decorative: "splash-glow", bundle: .module)
			  .resizable()
			  .aspectRatio(1, contentMode: .fit)
			  .frame(maxWidth: 340, maxHeight: 340)
			  .offset(x: -7, y: 38)

			Image(decorative: "brand-logo", bundle: .module)
			  .resizable()
			  .scaledToFit()
			  .frame(maxWidth: 375, maxHeight: 318)
			  .offset(x: 10.5)
			  .padding(.top, 6)
		  }
		  .frame(maxWidth: .infinity)

          Text(viewModel.subheadline)
            .font(.system(size: 16))
            .foregroundStyle(theme.brandSecondaryText)
            .lineSpacing(7)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 36)
		  Text(viewModel.subheadline2)
			.font(.system(size: 14))
			.foregroundStyle(theme.brandSecondaryText)
			.lineSpacing(7)
			.fixedSize(horizontal: false, vertical: true)
			.padding(.top, 36)
          badges
            .padding(.top, 44)

          Spacer(minLength: 24)

          BrandPrimaryButton(title: viewModel.signUpLabel) {
            router.push(.createAccount)
          }
          .accessibilityIdentifier("welcome_sign_up")

          Button {
            router.push(.login)
          } label: {
            Text(viewModel.logInLabel)
              .font(.system(size: 15, weight: .bold))
              .foregroundStyle(theme.brandActionBackground)
          }
          .buttonStyle(.plain)
          .frame(maxWidth: .infinity)
          .padding(.top, 20)
          .padding(.bottom, 28)
          .accessibilityIdentifier("welcome_log_in")
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: .infinity)
        .frame(minHeight: proxy.size.height, alignment: .top)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Image("AppIcon", bundle: .module)
        .resizable()
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 7))
      Text(viewModel.appName)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(theme.onDarkFill)

      Spacer()
    }
  }

  private var badges: some View {
    HStack(spacing: 12) {
      badge(viewModel.verifiedTutorsBadge, systemImage: "checkmark.seal")
      Spacer(minLength: 0)
      badge(viewModel.privacyProtectedBadge, systemImage: "lock.fill")
    }
  }

  /// A claim the app makes, as a brand chip.
  private func badge(_ title: String, systemImage: String) -> some View {
    HStack(spacing: 7) {
      PlatformIcon(systemName: systemImage, size: 12, weight: .medium, color: theme.brandActionBackground)
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.onDarkFill)
    }
    .padding(.horizontal, 13)
    .frame(height: 37)
    .background(theme.brandCardSurface)
    .clipShape(Capsule())
    .overlay {
      Capsule()
        .stroke(theme.brandControlBorder, lineWidth: 1)
    }
  }
}

#if os(iOS)
struct WelcomeView_Previews: PreviewProvider {
  static var previews: some View {
    WelcomeView()
  }
}
#endif
