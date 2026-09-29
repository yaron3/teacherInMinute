//
//  BrandSideMenuView.swift
//  teacher-minute
//
//  The app's navigation, as the brand design draws it: a dark panel from the
//  left edge with the sections, and the user's email and phone at its foot.
//  Home is the only screen on the root; every other section is picked from
//  this menu or from the tab bar.
//

import SwiftUI

// MARK: - Environment

/// What a screen's menu button does. `MainTabView` supplies it to whichever
/// section it is showing; outside that screen it is absent, and
/// `BrandMenuButton` draws nothing.
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

// MARK: - Menu

struct BrandSideMenuView: View {
  let viewModel: MainTabViewModel
  let profile: ProfileViewModel
  /// For a student without an account yet, who has one to log in to.
  let onLogIn: () -> Void

  /// The language's direction. The panel itself is laid out left to right in
  /// both languages, as designed; only sentences read in this one.
  @Environment(\.layoutDirection) var layoutDirection
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    ZStack(alignment: .leading) {
      if viewModel.isSideMenuOpen {
        // `MainTabView` blurs what this covers: SwiftUI has no backdrop blur.
        theme.scrim.opacity(0.5)
          .ignoresSafeArea()
          .onTapGesture { viewModel.closeSideMenu() }
          .transition(.opacity)

        panel
          .transition(.move(edge: .leading))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .animation(.easeOut(duration: 0.25), value: viewModel.isSideMenuOpen)
    .readingDirection(.leftToRight)
  }

  var panel: some View {
    VStack(alignment: .leading, spacing: 24) {
      header

      VStack(spacing: 4) {
        ForEach(viewModel.menuItems, id: \.self) { item in
          row(item)
        }
      }

      Spacer(minLength: 0)

      footer
    }
    .padding(.top, 16)
    .padding(.bottom, 24)
    .padding(.leading, 16)
    // 16, inside the 1pt edge on the right.
    .padding(.trailing, 17)
    .frame(width: 280)
    .frame(maxHeight: .infinity)
    .background {
      HStack(spacing: 0) {
        theme.brandBackgroundTop
        theme.brandControlBorder
          .frame(width: 1)
      }
      .ignoresSafeArea()
    }
  }

  /// The way out on the left, the title on the right.
  var header: some View {
    HStack(spacing: 12) {
      Button {
        viewModel.closeSideMenu()
      } label: {
        Image("brand-close-circle", bundle: .module)
          .renderingMode(.template)
          .resizable()
          .foregroundStyle(theme.onDarkFill)
          .frame(width: 20, height: 20)
          .frame(width: 40, height: 40)
          .background(theme.brandCardSurface)
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay {
            RoundedRectangle(cornerRadius: 10)
              .stroke(theme.brandControlBorder, lineWidth: 1)
          }
      }
      .buttonStyle(.plain)
#if !os(Android)
      // SkipUI has no string `accessibilityLabel`.
      .accessibilityLabel(viewModel.closeMenuLabel)
#endif
      .accessibilityIdentifier("side_menu_close")

      Spacer(minLength: 0)

      Text(viewModel.menuTitle)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .lineLimit(1)
    }
  }

  /// The icon, then the name. The row on screen is filled cyan.
  func row(_ item: MenuItem) -> some View {
    let isSelected = viewModel.isSelected(item)
    let tint = isSelected ? theme.onBrandAction : theme.brandActionBackground
    return Button {
      viewModel.select(item)
    } label: {
      HStack(spacing: 12) {
        icon(for: item, isSelected: isSelected, tint: tint)
          .frame(width: 32, height: 32)

        Text(item.title)
          .font(.system(size: 16, weight: isSelected ? .bold : .medium))
          .foregroundStyle(isSelected ? theme.onBrandAction : theme.brandSecondaryText)
          .lineLimit(1)

        Spacer(minLength: 0)

        if viewModel.showsBadge(item) {
          BrandBadgeDot()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      // Opaque, so the whole row takes the tap: `contentShape` is not
      // available in Skip's SwiftUI.
      .background(isSelected ? theme.brandActionBackground : theme.brandBackgroundTop)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("side_menu_item_\(item.identifier)")
  }

  /// Each icon at the size the design gives it, in a 28pt box.
  @ViewBuilder
  func icon(for item: MenuItem, isSelected: Bool, tint: Color) -> some View {
    if let icon = item.brandIcon {
      menuIcon(icon.name, width: icon.size.width, height: icon.size.height, tint: tint)
    } else {
      // Help & Support is not in the design, and keeps the icon it had.
      PlatformIcon(systemName: item.tab.systemImage(isSelected: isSelected), size: 22, color: tint)
        .frame(width: 28, height: 28)
    }
  }

  func menuIcon(_ name: String, width: CGFloat, height: CGFloat, tint: Color) -> some View {
    Image(name, bundle: .module)
      .renderingMode(.template)
      .resizable()
      .foregroundStyle(tint)
      .frame(width: width, height: height)
      .frame(width: 28, height: 28)
  }

  /// The user's email and phone, or for a student without an account, the
  /// way to log in to one.
  @ViewBuilder
  var footer: some View {
    if viewModel.isAnonymousAccount {
      logInRow
    } else {
      VStack(alignment: .leading, spacing: 12) {
        if !profile.email.isEmpty {
          contactRow(icon: "brand-contact-email", label: viewModel.emailLabel, value: profile.email)
        }
        if !profile.phoneNumber.isEmpty {
          contactRow(icon: "brand-contact-phone", label: viewModel.phoneLabel, value: profile.phoneNumber)
        }
      }
    }
  }

  func contactRow(icon: String, label: String, value: String) -> some View {
    HStack(spacing: 12) {
      Image(decorative: icon, bundle: .module)
        .resizable()
        .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 4) {
        Text(label)
          .font(.system(size: 13))
          .foregroundStyle(theme.brandSecondaryText)
          .lineLimit(1)
        Text(value)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }

      Spacer(minLength: 0)
    }
    .frame(height: 42)
  }

  /// A sentence, so it reads in the language's direction, unlike the panel.
  var logInRow: some View {
    HStack(spacing: 4) {
      Text(viewModel.alreadyHaveAccountText)
        .foregroundStyle(theme.brandSecondaryText)
      Button {
        onLogIn()
      } label: {
        Text(viewModel.logInLabel)
          .fontWeight(.bold)
          .foregroundStyle(theme.brandActionBackground)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("side_menu_log_in")
    }
    .font(.system(size: 14))
    .environment(\.layoutDirection, layoutDirection)
  }
}
