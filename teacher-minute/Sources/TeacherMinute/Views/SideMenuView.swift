//
//  SideMenuView.swift
//  teacher-minute
//
//  The app's main navigation. Home is the only screen on the root; every other
//  section — lessons, earnings, profile, settings — is picked from this drawer,
//  which slides in from the leading edge (the right, in Hebrew).
//

import SwiftUI

// MARK: - Environment

/// What a screen's menu button does. `MainTabView` supplies it to whichever
/// section it is showing; outside that screen it is absent, and
/// `SideMenuButton` draws nothing.
struct SideMenuAction: Sendable {
  let accessibilityLabel: String
  /// A dot on the button, for news waiting inside the menu (new lessons).
  let showsBadge: Bool
  let open: @MainActor @Sendable () -> Void
}

private struct SideMenuActionKey: EnvironmentKey {
  static let defaultValue: SideMenuAction? = nil
}

extension EnvironmentValues {
  var sideMenuAction: SideMenuAction? {
	get { self[SideMenuActionKey.self] }
	set { self[SideMenuActionKey.self] = newValue }
  }
}

// MARK: - Hamburger button

/// The round button that opens the side menu. Each section places it in its
/// own header, so it sits where that screen's layout wants it.
struct SideMenuButton: View {
  var size: CGFloat = 44
  @Environment(\.sideMenuAction) var action
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
	if let action {
	  Button {
		action.open()
	  } label: {
		ZStack(alignment: .topTrailing) {
		  Circle()
			.fill(theme.cardBackground)
			.frame(width: size, height: size)
			.overlay {
			  PlatformIcon(systemName: "line.3.horizontal", size: 17, weight: .semibold, color: theme.primaryText)
			}

		  if action.showsBadge {
			Circle()
			  .fill(theme.accent)
			  .frame(width: 9, height: 9)
			  // Inset rather than pushed past the edge: a navigation bar clips
			  // anything outside the button's frame. Padding also needs no
			  // flipping for right-to-left.
			  .padding(2)
		  }
		}
	  }
	  .buttonStyle(.plain)
#if !os(Android)
	  // SkipUI has no string `accessibilityLabel`.
	  .accessibilityLabel(action.accessibilityLabel)
#endif
	  .accessibilityIdentifier("side_menu_button")
	}
  }
}

/// A section title with the menu button beside it, drawn in the content.
///
/// For Settings and Help on Android, which would otherwise take both from the
/// navigation bar. SkipUI leaves a large gap above a root screen whose title
/// sits in the bar, while screens that hide the bar and draw their own header
/// (Home, Profile) lay out correctly. Seen on SkipUI 1.53.1 and still there on
/// 1.60.0, so check on Android before taking this out after an upgrade.
struct SideMenuSectionHeader: View {
  let title: String
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
	HStack(spacing: 12) {
	  SideMenuButton(size: 36)

	  Text(title)
		.font(.system(size: 24, weight: .bold))
		.foregroundStyle(theme.primaryText)

	  Spacer()
	}
	.padding(.horizontal, 16)
	.padding(.vertical, 8)
  }
}

// MARK: - Drawer

struct SideMenuView: View {
  let viewModel: MainTabViewModel
  let profile: ProfileViewModel
  let onLogOut: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
	ZStack(alignment: .leading) {
	  if viewModel.isSideMenuOpen {
		theme.scrim.opacity(0.35)
		  .ignoresSafeArea()
		  .onTapGesture { viewModel.closeSideMenu() }
		  .transition(.opacity)

		panel
		  .frame(width: 300)
		  .frame(maxHeight: .infinity)
		  .background(theme.screenBackground.ignoresSafeArea())
		  .transition(.move(edge: .leading))
	  }
	}
	.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
	.animation(.easeOut(duration: 0.25), value: viewModel.isSideMenuOpen)
  }

  var panel: some View {
	VStack(alignment: .leading, spacing: 0) {
	  header
		.padding(.horizontal, 16)
		.padding(.top, 12)
		.padding(.bottom, 20)

	  ScrollView(.vertical, showsIndicators: false) {
		VStack(spacing: 4) {
		  ForEach(viewModel.primaryMenuTabs, id: \.self) { tab in
			tabRow(tab)
		  }

		  FlatRule()
			.padding(.vertical, 12)

		  ForEach(viewModel.secondaryMenuTabs, id: \.self) { tab in
			tabRow(tab)
		  }
		}
		.padding(.horizontal, 12)
	  }

	  Spacer(minLength: 0)

	  FlatRule()

	  logOutRow
		.padding(.horizontal, 12)
		.padding(.vertical, 12)
	}
  }

  var header: some View {
	VStack(alignment: .leading, spacing: 16) {
	  HStack {
		Spacer()
		Button {
		  viewModel.closeSideMenu()
		} label: {
		  PlatformIcon(systemName: "xmark", size: 17, weight: .semibold, color: theme.primaryText)
			.frame(width: 36, height: 36)
		}
		.buttonStyle(.plain)
#if !os(Android)
		.accessibilityLabel(viewModel.closeMenuLabel)
#endif
		.accessibilityIdentifier("side_menu_close")
	  }

	  HStack(spacing: 12) {
		ProfileAvatarView(
		  imageURL: profile.profileImageURL,
		  size: 52,
		  fallbackSystemImage: "person.crop.circle.fill",
		  background: theme.cardBackground,
		  tint: theme.primaryText
		)

		VStack(alignment: .leading, spacing: 2) {
		  Text(profile.menuDisplayName)
			.font(.system(size: 17, weight: .bold))
			.foregroundStyle(theme.primaryText)
			.lineLimit(1)

		  if !profile.email.isEmpty {
			Text(profile.email)
			  .font(.system(size: 13))
			  .foregroundStyle(theme.secondaryText)
			  .lineLimit(1)
		  }
		}
	  }
	}
  }

  func tabRow(_ tab: MainTab) -> some View {
	let isSelected = viewModel.selectedTab == tab
	let badge = viewModel.badgeCount(for: tab)
	return Button {
	  viewModel.select(tab)
	} label: {
	  HStack(spacing: 14) {
		MainTabIcon(tab: tab, isSelected: isSelected, size: 22)
		  .foregroundStyle(isSelected ? theme.accent : theme.primaryText)
		  .frame(width: 34, height: 34)

		Text(tab.title)
		  .font(.system(size: 16, weight: isSelected ? .bold : .medium))
		  .foregroundStyle(isSelected ? theme.accent : theme.primaryText)

		Spacer()

		if badge > 0 {
		  Text("\(badge)")
			.font(.system(size: 12, weight: .bold))
			.foregroundStyle(theme.onAccentText)
			.frame(minWidth: 22, minHeight: 22)
			.background(theme.accent)
			.clipShape(Capsule())
		}
	  }
	  .padding(.horizontal, 12)
	  .frame(height: 48)
	  // An opaque background keeps the whole row tappable; `contentShape` is
	  // not available in Skip's SwiftUI.
	  .background(isSelected ? theme.accentBackground : theme.screenBackground)
	  .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
	}
	.buttonStyle(.plain)
	.accessibilityIdentifier("side_menu_item_\(tab.identifier)")
  }

  var logOutRow: some View {
	Button {
	  onLogOut()
	} label: {
	  HStack(spacing: 14) {
		PlatformIcon(systemName: "rectangle.portrait.and.arrow.right", size: 20, color: theme.danger)
		  .frame(width: 34, height: 34)

		Text(viewModel.logOutLabel)
		  .font(.system(size: 16, weight: .medium))
		  .foregroundStyle(theme.danger)

		Spacer()
	  }
	  .padding(.horizontal, 12)
	  .frame(height: 48)
	  .background(theme.screenBackground)
	}
	.buttonStyle(.plain)
	.accessibilityIdentifier("side_menu_log_out")
  }
}

// MARK: - Section icon

/// The icon for a section, filled while it is the selected one.
struct MainTabIcon: View {
  let tab: MainTab
  let isSelected: Bool
  var size: CGFloat = 22
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
	let name = tab.systemImage(isSelected: isSelected)
	if tab == .lessons || tab == .profile {
	  // Bundled asset, not an SF Symbol. The artwork carries its own padding
	  // (it was drawn for the tab bar), so it gets a larger frame than a symbol.
	  Image(name, bundle: .module)
		.renderingMode(.template)
		.resizable()
		.aspectRatio(contentMode: .fit)
		.frame(width: size * 1.55, height: size * 1.55)
	} else {
	  // SkipUI maps only a subset of SF Symbols, so Android goes through the
	  // app's own icon table. Tinted to match the row, which is why the color
	  // is picked here rather than inherited.
	  PlatformIcon(
		systemName: name,
		size: size,
		color: isSelected ? theme.accent : theme.primaryText
	  )
	}
  }
}
