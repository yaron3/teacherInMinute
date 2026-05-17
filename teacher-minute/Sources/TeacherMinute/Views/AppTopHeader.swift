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
  var showNotificationBadge = false
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  
  var body: some View {
	HStack(spacing: 10) {
	  Circle()
		.fill(theme.appPurpleSoft)
		.frame(width: 38, height: 38)
		.overlay {
		  PlatformIcon(systemName: avatarSystemImage, size: 18, weight: .semibold, color: theme.appPurple)
		}
	  
	  VStack(alignment: .leading, spacing: 2) {
		Text(eyebrow)
		  .font(.system(size: 11))
		  .foregroundStyle(theme.appSecondaryText)
		
		Text(name)
		  .font(.system(size: 15, weight: .bold))
		  .foregroundStyle(theme.appPrimaryText)
	  }
	  
	  Spacer()
	  
	  Button {
		// TODO: open notifications
	  } label: {
		ZStack(alignment: .topTrailing) {
		  Circle()
			.fill(theme.appPrimaryText)
			.frame(width: 42, height: 42)
			.shadow(color: theme.appPrimaryText.opacity(0.05), radius: 12, x: 0, y: 6)
			.overlay {
			  PlatformIcon(systemName: "bell.fill", size: 15, weight: .semibold, color: theme.appOrange)
			}
		  
		  if showNotificationBadge {
			Circle()
			  .fill(theme.appPink)
			  .frame(width: 8, height: 8)
			  .offset(x: -8, y: 8)
		  }
		}
	  }
	  .buttonStyle(.plain)
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
	  .background(theme.appCardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	  .shadow(color: theme.appPrimaryText.opacity(0.035), radius: 18, x: 0, y: 10)
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
	  .foregroundStyle(foreground ?? theme.appPink)
	  .padding(.horizontal, 10)
	  .frame(height: 24)
	  .background(background ?? theme.appPinkSoft)
	  .clipShape(Capsule())
  }
}
