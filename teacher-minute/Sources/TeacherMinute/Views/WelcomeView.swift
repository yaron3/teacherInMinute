//
//  WelcomeView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 05/05/2026.
//

import SwiftUI

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

struct WelcomeView: View {
  @Environment(\.appRouter) var router
  @State var isCheckingSession = true
  
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  
  var body: some View {
	ZStack {
	  Color(.systemBackground)
		.ignoresSafeArea()
	  
      if isCheckingSession {
        ProgressView()
          .progressViewStyle(.circular)
          .scaleEffect(1.4)
      } else {
        welcomeContent
      }
	}
	  .task { await resumeExistingSessionIfNeeded() }
  }

  private var welcomeContent: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      
      Text(LocalizationSupport.localized("Help you any where"))
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
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(theme.primaryBackground)
          .frame(maxWidth: .infinity)
          .frame(height: 62)
          .background(theme.primaryText)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
  }
  
  private func resumeExistingSessionIfNeeded() async {
	#if !targetEnvironment(preview)
	defer { isCheckingSession = false }
	guard router.path.isEmpty else { return }
	guard let uid = Auth.auth().currentUser?.uid else { return }
	
	do {
	  let resume = try await UserService.shared.resumeRoute(uid: uid)
	  router.replace(with: AppRoute.resumeDestination(for: resume))
	  logger.info("[Auth] auto-login restored session uid=\(uid)")
	} catch {
	  logger.error("[Auth] auto-login failed: \(error)")
	}
	#endif
  }
  
  private var header: some View {
	HStack(spacing: 12) {
	  RoundedRectangle(cornerRadius: 9, style: .continuous)
		.fill(theme.primaryBackground)
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
	  RoundedRectangle(cornerRadius: 16, style: .continuous)
		.fill(theme.previewBackground)
		.overlay {
		  RoundedRectangle(cornerRadius: 16, style: .continuous)
			.stroke(theme.appPrimaryText.opacity(0.04), lineWidth: 1)
		}
		.shadow(color: theme.appPrimaryText.opacity(0.035), radius: 18, x: 0, y: 12)
	  
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
		title: "Verified Tutors",
		systemImage: "checkmark.seal",
		foreground: theme.greenText,
		background: theme.greenBackground,
		border: theme.greenBorder
	  )
	  Spacer()
	  BadgeView(
		title: "Privacy Protected",
		systemImage: "lock.fill",
		foreground: theme.badgeGrayText,
		background: theme.grayBadgeBackground,
		border: theme.grayBadgeBorder
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
