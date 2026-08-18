//
//  AppTopHeader.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct AppTopHeader: View {
  let avatarSystemImage: String
  let eyebrow: String
  let name: String
  var avatarImageURL = ""
  var showNotificationBadge = false
  var onMessagesDismissed: (() -> Void)?
  @State var showsMessages = false
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  
  var body: some View {
	HStack(spacing: 10) {
      ProfileAvatarView(
        imageURL: avatarImageURL,
        size: 38,
        fallbackSystemImage: avatarSystemImage,
        background: theme.accentBackground,
        tint: theme.accentStrong
      )
	  
	  VStack(alignment: .leading, spacing: 2) {
		Text(LocalizedStringKey(eyebrow))
		  .font(.system(size: 11))
		  .foregroundStyle(theme.secondaryText)
		
		Text(name)
		  .font(.system(size: 15, weight: .bold))
		  .foregroundStyle(theme.primaryText)
	  }
	  
	  Spacer()
	  
	  Button {
			showsMessages = true
	  } label: {
		ZStack(alignment: .topTrailing) {
		  Circle()
			.fill(theme.cardBackground)
			.frame(width: 42, height: 42)
			.shadow(color: theme.cardShadow.opacity(0.05), radius: 12, x: 0, y: 6)
			.overlay {
			  PlatformIcon(systemName: "bell.fill", size: 15, weight: .semibold, color: theme.primaryText)
			}
		  
		  if showNotificationBadge {
			Circle()
			  .fill(theme.accent)
			  .frame(width: 8, height: 8)
			  .offset(x: -8, y: 8)
		  }
		}
	  }
	  .buttonStyle(.plain)
	}
    .sheet(isPresented: $showsMessages, onDismiss: {
      onMessagesDismissed?()
    }) {
      NotificationMessagesView()
    }
  }
}

struct RoundedInfoCard<Content: View>: View {
  let content: Content
  
  init(@ViewBuilder content: () -> Content) {
	self.content = content()
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	content
	  .padding(18)
	  .background(theme.cardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	  .shadow(color: theme.cardShadow.opacity(0.035), radius: 18, x: 0, y: 10)
  }
}

struct SmallPill: View {
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  let title: String
  var foreground: Color?
  var background: Color?
  
  var body: some View {
	Text(title)
	  .font(.system(size: 11, weight: .semibold))
	  .foregroundStyle(foreground ?? theme.accent)
	  .padding(.horizontal, 10)
	  .frame(height: 24)
	  .background(background ?? theme.accentBackground)
	  .clipShape(Capsule())
  }
}
