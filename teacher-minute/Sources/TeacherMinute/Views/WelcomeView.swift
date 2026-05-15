//
//  SwiftUIView.swift
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
      
      Text("Help you any where")
        .font(.system(size: 35, weight: .bold, design: .default))
        .foregroundStyle(Color.primaryText)
        .lineSpacing(-4)
        .padding(.top, 42)
      
      Image("student")
        .resizable()
        .scaledToFit()
        .padding(.top, 32)
      
      Text("Connect instantly with verified math\nteachers for on-demand help, or share your\nexpertise.")
        .font(.system(size: 16, weight: .regular))
        .foregroundStyle(Color.secondaryText)
        .lineSpacing(7)
        .padding(.top, 36)
      
      badges
        .padding(.top, 44)
      
      Spacer(minLength: 24)
      
      Button {
        router.push(.createAccount)
      } label: {
        Text("Sign Up")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 62)
          .background(Color.primaryText)
          .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      
      HStack(spacing: 4) {
        Text("Already have an account?")
          .foregroundStyle(Color.secondaryText)
        
        Button {
          router.push(.login)
        } label: {
          Text("Log In")
            .fontWeight(.semibold)
            .foregroundStyle(Color.primaryText)
        }
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
  }
  
  private var header: some View {
	HStack(spacing: 12) {
	  RoundedRectangle(cornerRadius: 9, style: .continuous)
		.fill(Color.primaryText)
		.frame(width: 34, height: 34)
		.overlay {
		  PlatformIcon(systemName: "graduationcap.fill")
			.font(.system(size: 15, weight: .semibold))
			.foregroundStyle(.white)
		}
	  
	  Text("Teacher in a Minute")
		.font(.system(size: 16, weight: .semibold))
		.foregroundStyle(Color.primaryText)
	  
	  Spacer()
	}
  }
  
  private var previewCard: some View {
	ZStack(alignment: .topLeading) {
	  RoundedRectangle(cornerRadius: 16, style: .continuous)
		.fill(Color.previewBackground)
		.overlay {
		  RoundedRectangle(cornerRadius: 16, style: .continuous)
			.stroke(Color.black.opacity(0.04), lineWidth: 1)
		}
		.shadow(color: .black.opacity(0.035), radius: 18, x: 0, y: 12)
	  
	  HStack(spacing: 0) {
		PlatformIcon(systemName: "photo")
		  .font(.system(size: 15))
		  .foregroundStyle(Color.secondaryText)
		
		Text("App Preview")
		  .font(.system(size: 16))
		  .foregroundStyle(Color.primaryText)
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
		foreground: Color.greenText,
		background: Color.greenBackground,
		border: Color.greenBorder
	  )
	  
	  BadgeView(
		title: "Privacy Protected",
		systemImage: "lock.fill",
		foreground: Color.badgeGrayText,
		background: Color.grayBadgeBackground,
		border: Color.grayBadgeBorder
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
	  
	  Text(title)
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
extension Color {
  static let primaryText = Color(red: 18 / 255, green: 24 / 255, blue: 40 / 255)
  static let secondaryText = Color(red: 102 / 255, green: 112 / 255, blue: 133 / 255)
  
  static let previewBackground = Color(red: 252 / 255, green: 252 / 255, blue: 253 / 255)
  
  static let greenText = Color(red: 2 / 255, green: 122 / 255, blue: 72 / 255)
  static let greenBackground = Color(red: 236 / 255, green: 253 / 255, blue: 243 / 255)
  static let greenBorder = Color(red: 186 / 255, green: 244 / 255, blue: 210 / 255)
  
  static let badgeGrayText = Color(red: 52 / 255, green: 64 / 255, blue: 84 / 255)
  static let grayBadgeBackground = Color(red: 249 / 255, green: 250 / 255, blue: 251 / 255)
  static let grayBadgeBorder = Color(red: 242 / 255, green: 244 / 255, blue: 247 / 255)
}

#if os(iOS)
struct WelcomeView_Previews: PreviewProvider {
  
  static var previews: some View {
	
	WelcomeView()
	
  }
  
}
#endif
