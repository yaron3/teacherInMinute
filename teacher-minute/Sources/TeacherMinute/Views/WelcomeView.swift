//
//  WelcomeView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 05/05/2026.
//

import SwiftUI

struct WelcomeView: View {
  @Environment(\.appRouter) var router

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
	ZStack {
	  theme.screenBackground
		.ignoresSafeArea()

	  welcomeContent
	}
  }

  private var welcomeContent: some View {
    GeometryReader { proxy in
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {
          header
          
          Text(LocalizationSupport.localized("Help you anywhere"))
            .font(.system(size: 35, weight: .bold, design: .default))
            .foregroundStyle(theme.primaryText)
            .lineSpacing(-4)
            .padding(.top, 42)
          
          Image("student")
            .resizable()
            .scaledToFit()
            .padding(.top, 32)
          
          Text(LocalizationSupport.localized("Connect instantly with verified math\nteachers for on-demand help, or share your\nexpertise."))
            .font(.system(size: 16, weight: .regular))
            .foregroundStyle(theme.secondaryText)
            .lineSpacing(7)
            .padding(.top, 36)
          
          badges
            .padding(.top, 44)
          
          Spacer(minLength: 24)
          
          Button {
            router.push(.createAccount)
          } label: {
            Text(LocalizationSupport.localized("Sign Up"))
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(theme.onAccentText)
              .frame(maxWidth: .infinity)
              .frame(height: 56)
              .background(theme.accent)
              .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
          }
          
        Button {
          router.push(.login)
        } label: {
          Text(LocalizationSupport.localized("Already have an account? Log In"))
            .fontWeight(.semibold)
            .foregroundStyle(theme.primaryText)
        }
      
      .font(.system(size: 15))
      .frame(maxWidth: .infinity)
      .padding(.top, 20)
      .padding(.bottom, 28)
        }
        .padding(.horizontal, 28)
        .padding(.top, 50)
        .frame(maxWidth: .infinity)
        .frame(minHeight: proxy.size.height, alignment: .top)
      }
    }
  }
  
  private var header: some View {
	HStack(spacing: 12) {
	  RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous)
		.fill(theme.screenBackground)
		.frame(width: 34, height: 34)
		.overlay {
		  PlatformIcon(
			systemName: "graduationcap.fill",
			size: 15,
			weight: .semibold,
			color: theme.primaryText
		  )
		}
	  
	  Text(LocalizationSupport.localized("Teacher in a Minute"))
		.font(.system(size: 16, weight: .semibold))
		.foregroundStyle(theme.primaryText)
	  
	  Spacer()
	}
  }
  
  private var previewCard: some View {
	ZStack(alignment: .topLeading) {
	  RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
		.fill(theme.cardBackground)
		.overlay {
		  RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
			.stroke(theme.separator, lineWidth: 1)
		}
	  
	  HStack(spacing: 0) {
		PlatformIcon(
		  systemName: "photo",
		  size: 15,
		  color: theme.secondaryText
		)
		
		Text(LocalizationSupport.localized("App Preview"))
		  .font(.system(size: 16))
		  .foregroundStyle(theme.primaryText)
	  }
	  .offset(x: 0, y: 2)
	}
	.frame(maxWidth: .infinity)
	.frame(height: 291)
  }
  
  private var badges: some View {
	HStack(spacing: 12) {
	  BadgeView(
		title: LocalizationSupport.localized("Verified Tutors"),
		systemImage: "checkmark.seal",
		foreground: theme.positive,
		background: theme.positiveBackground,
		border: theme.positiveBorder
	  )
	  Spacer()
	  BadgeView(
		title: LocalizationSupport.localized("Privacy Protected"),
		systemImage: "lock.fill",
		foreground: theme.badgeText,
		background: theme.badgeBackground,
		border: theme.badgeBorder
	  )
	}
  }
}

struct BadgeView: View {
  let title: String
  let systemImage: String
  let foreground: Color
  let background: Color
  let border: Color
  
  var body: some View {
	HStack(spacing: 7) {
	  PlatformIcon(systemName: systemImage)
		.font(.system(size: 12, weight: .medium))
	  
	  Text(LocalizationSupport.localized(title))
		.font(.system(size: 13, weight: .medium))
	}
	.foregroundStyle(foreground)
	.padding(.horizontal, 13)
	.frame(height: 37)
	.background(background)
	.overlay {
	  Capsule()
		.stroke(border, lineWidth: 5)
	}
	.clipShape(Capsule())
  }
}

#if os(iOS)
struct WelcomeView_Previews: PreviewProvider {
  
  static var previews: some View {
	
	WelcomeView()
	
  }
  
}
#endif
