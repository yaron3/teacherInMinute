//
//  BrandTabScreens.swift
//  teacher-minute
//
//  What the sections share, in both apps: the tab bar along the bottom (on
//  every one but a student's Home), the header with the way to the menu or
//  back, and the controls their cards are built from.
//

import SwiftUI

// MARK: - Tab bar environment

/// The tab bar's tabs, the one on screen, what a tap does, and which tabs
/// have news waiting. `MainTabView` supplies it to the sections; without it
/// `BrandTabBar` draws nothing.
struct TabBarAction: Sendable {
  let items: [MenuItem]
  let selected: MenuItem?
  let badged: Set<MenuItem>
  let select: @MainActor @Sendable (MenuItem) -> Void
}

private struct TabBarActionKey: EnvironmentKey {
  static let defaultValue: TabBarAction? = nil
}

extension EnvironmentValues {
  var tabBarAction: TabBarAction? {
    get { self[TabBarActionKey.self] }
    set { self[TabBarActionKey.self] = newValue }
  }
}

extension MenuItem {
  /// The item's icon in the brand's set, at the size the design draws it in
  /// its 28pt box. Pro Teacher's Home and Earnings are drawn in the same
  /// line style; its Lessons share Activity's. Help & Support has none: it
  /// keeps its system icon.
  var brandIcon: (name: String, size: CGSize)? {
    switch self {
    case .ask: ("brand-menu-ask", CGSize(width: 28, height: 28))
    case .minutes: ("brand-menu-minutes", CGSize(width: 28, height: 28))
    case .activity, .lessons: ("brand-menu-activity", CGSize(width: 26, height: 28))
    case .home: ("brand-menu-home", CGSize(width: 24, height: 24))
    case .earnings: ("brand-menu-earnings", CGSize(width: 24, height: 24))
    case .profile: ("brand-menu-profile", CGSize(width: 18, height: 18))
    case .settings: ("brand-menu-settings", CGSize(width: 23, height: 23))
    case .help, .tutorial: nil
    }
  }
}

// MARK: - Screens

/// A section on the brand's dark ground: its content, then the tab bar.
///
/// A screen's `.task`, `.onChange` and sheets go on a plain stack inside its
/// content, not on this: on Android, SkipUI never ran a `.task` put on this
/// container, while the same `.task` on a stack inside it did.
struct BrandTabScreen<Content: View>: View {
  let content: Content
  let showsGlow: Bool

  init(showsGlow: Bool = false, @ViewBuilder content: () -> Content) {
    self.showsGlow = showsGlow
    self.content = content()
  }

  var body: some View {
    ZStack {
      BrandScreenBackground(streaks: .tabs, showsGlow: showsGlow)
      VStack(spacing: 0) {
        VStack(spacing: 0) {
          content
        }
        .frame(maxHeight: .infinity, alignment: .top)
        BrandTabBar()
      }
    }
    .environment(\.colorScheme, .dark)
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
  }
}

/// A page pushed from a section, or a step of onboarding: the brand's
/// ground without the tab bar, and the way back in its header. As with
/// `BrandTabScreen`, a page's modifiers go on its content.
struct BrandSubpage<Content: View>: View {
  let label: String
  let title: String
  let backLabel: String
  /// False for a page whose content scrolls itself, a web page's.
  var scrolls = true
  /// What the back button does, when it is not to dismiss the page: an
  /// onboarding step walks back through its own handler.
  var onBack: (() -> Void)?
  let content: Content

  @Environment(\.dismiss) var dismiss

  init(
    label: String,
    title: String,
    backLabel: String,
    scrolls: Bool = true,
    onBack: (() -> Void)? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.label = label
    self.title = title
    self.backLabel = backLabel
    self.scrolls = scrolls
    self.onBack = onBack
    self.content = content()
  }

  var body: some View {
    ZStack {
      BrandScreenBackground(streaks: .subpage)
      VStack(spacing: 0) {
        BrandPageHeader(label: label, title: title) {
          BrandBackButton(accessibilityLabel: backLabel) {
            if let onBack {
              onBack()
            } else {
              dismiss()
            }
          }
        }
        if scrolls {
          ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
              content
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 20)
          }
        } else {
          VStack(alignment: .leading, spacing: 16) {
            content
          }
          .padding(.horizontal, 20)
          .padding(.top, 16)
          .frame(maxHeight: .infinity, alignment: .top)
        }
      }
    }
    .environment(\.colorScheme, .dark)
    .toolbar(.hidden, for: .navigationBar)
    .navigationBarBackButtonHidden(true)
    .systemBarIcons(darkStatusBar: false, darkNavigationBar: false)
  }
}

/// A sheet on the brand's ground: its title and the way out in a header,
/// then its content. As with `BrandTabScreen`, a sheet's modifiers go on its
/// content.
struct BrandSheet<Content: View>: View {
  let title: String
  let closeLabel: String
  let onClose: () -> Void
  let content: Content

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(title: String, closeLabel: String, onClose: @escaping () -> Void, @ViewBuilder content: () -> Content) {
    self.title = title
    self.closeLabel = closeLabel
    self.onClose = onClose
    self.content = content()
  }

  var body: some View {
    ZStack {
      BrandScreenBackground()
      VStack(spacing: 0) {
        BrandPageHeader(label: "", title: title) {
          BrandCloseButton(accessibilityLabel: closeLabel) {
            onClose()
          }
          .accessibilityIdentifier("brand_sheet_close")
        }
        ScrollView(.vertical, showsIndicators: false) {
          VStack(alignment: .leading, spacing: 16) {
            content
          }
          .padding(.horizontal, 20)
          .padding(.top, 8)
          .padding(.bottom, 20)
        }
      }
    }
    .environment(\.colorScheme, .dark)
  }
}

/// The square close button of a brand sheet's header: a crossed circle on
/// the card's surface.
struct BrandCloseButton: View {
  let accessibilityLabel: String
  let action: () -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button {
      action()
    } label: {
      Image("brand-close-circle", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.onDarkFill)
        .frame(width: 20, height: 20)
        .frame(width: 44, height: 44)
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
    .accessibilityLabel(accessibilityLabel)
#endif
  }
}

/// Settings rows in a brand card: the icon at the start, the name and what it
/// holds, and, where the design draws one, the chevron.
struct BrandSettingsRows: View {
  let rows: [SettingsRow]
  let select: (SettingsRow) -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach(rows) { row in
        if row.id != rows.first?.id {
          BrandRule()
        }
        rowButton(row)
      }
    }
    .brandCard()
  }

  /// As designed, only Preferences and Notifications carry the chevron.
  func rowButton(_ row: SettingsRow) -> some View {
    Button {
      select(row)
    } label: {
      HStack(spacing: 12) {
        rowIcon(row)
          .frame(width: 40, height: 40)

        VStack(alignment: .leading, spacing: 4) {
          Text(row.title)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(row.isDestructive ? theme.danger : theme.onDarkFill)
          if let subtitle = row.subtitle {
            Text(subtitle)
              .font(.system(size: 13))
              .foregroundStyle(theme.brandSecondaryText)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if row.action == .appPreferences || row.action == .notifications {
          BrandForwardChevron()
        }
      }
      .tappableFrame()
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("settings_row_\(row.action.id)")
  }

  /// The design's icon where it has one; otherwise a symbol SkipUI also draws
  /// on Android.
  @ViewBuilder
  func rowIcon(_ row: SettingsRow) -> some View {
    if let asset = Self.designedIcon(for: row.action) {
      Image(asset, bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.onDarkFill)
    } else {
      Image(systemName: Self.symbol(for: row))
        .resizable()
        .scaledToFit()
        .foregroundStyle(row.isDestructive ? theme.danger : theme.onDarkFill)
        .frame(width: 18, height: 18)
    }
  }

  static func designedIcon(for action: SettingsAction) -> String? {
    switch action {
    case .appPreferences: "brand-settings-preferences"
    case .language: "brand-settings-language"
    case .notifications: "brand-settings-notifications"
    case .privacyControls: "brand-settings-privacy"
    default: nil
    }
  }

  static func symbol(for row: SettingsRow) -> String {
    switch row.action {
    case .studentPayments: "cart"
    case .about: "info.circle"
    case .accountSecurity, .privacyPolicy: "lock"
    case .contactUs: "envelope"
    case .eula: "list.bullet"
    case .changePassword: "pencil"
    case .logOut: "arrow.forward.square"
    case .deleteAccount: "trash"
    default: row.systemImage
    }
  }
}

// MARK: - Tab bar

/// The sections, in the language's order: Ask, Minutes, Activity, Profile and
/// Settings for a student, Home, Lessons, Earnings, Profile and Settings for
/// a teacher. The tab on screen stands in a cyan box that rises above the
/// bar.
struct BrandTabBar: View {
  @Environment(\.tabBarAction) var action
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    if let action {
      HStack(alignment: .bottom, spacing: 0) {
        ForEach(action.items, id: \.self) { item in
          Button {
            action.select(item)
          } label: {
            tab(item, isSelected: item == action.selected)
              .overlay(alignment: .top) {
                if action.badged.contains(item) {
                  BrandBadgeDot()
                    .offset(x: 16, y: 8)
                }
              }
              .frame(maxWidth: .infinity)
              .tappableFrame()
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("tab_item_\(item.identifier)")
        }
      }
      .padding(.bottom, 10)
      // The bar is 74pt; the box of the tab on screen stands above it.
      .background(alignment: .bottom) {
        theme.brandCardSurface
          .frame(height: 74)
          .ignoresSafeArea(edges: .bottom)
      }
    }
  }

  @ViewBuilder
  func tab(_ item: MenuItem, isSelected: Bool) -> some View {
    if isSelected {
      VStack(spacing: 0) {
        icon(item, tint: theme.brandBackgroundTop)
          .frame(width: 54, height: 52)
          .background(theme.brandActionBackground)
          .clipShape(RoundedRectangle(cornerRadius: 10))
        label(item)
      }
    } else {
      // As designed, the name reaches 2pt up into the icon's 52pt box.
      ZStack(alignment: .top) {
        icon(item, tint: theme.brandActionBackground)
          .padding(.top, 12)
        label(item)
          .padding(.top, 38)
      }
    }
  }

  @ViewBuilder
  func icon(_ item: MenuItem, tint: Color) -> some View {
    if let icon = item.brandIcon {
      Image(icon.name, bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(tint)
        .frame(width: icon.size.width, height: icon.size.height)
        .frame(width: 28, height: 28)
    }
  }

  func label(_ item: MenuItem) -> some View {
    Text(item.title)
      .font(.system(size: 15, weight: .medium))
      .foregroundStyle(theme.brandActionBackground)
      .lineLimit(1)
      .minimumScaleFactor(0.8)
      .frame(height: 20)
  }
}

// MARK: - Header

/// A section's header: what it is and whose, then at the far end the way to
/// the menu or back.
struct BrandPageHeader<Accessory: View>: View {
  let label: String
  let title: String
  let accessory: Accessory

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(label: String, title: String, @ViewBuilder accessory: () -> Accessory) {
    self.label = label
    self.title = title
    self.accessory = accessory()
  }

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        if !label.isEmpty {
          Text(label)
            .font(.system(size: 13))
            .foregroundStyle(theme.brandSecondaryText)
            .lineLimit(1)
        }
        Text(title)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .lineLimit(1)
      }
      Spacer(minLength: 0)
      accessory
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }
}

/// The square button that opens the side menu, in the brand's style, with a
/// dot while news waits inside the menu.
struct BrandMenuButton: View {
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
        Image("brand-menu", bundle: .module)
          .renderingMode(.template)
          .resizable()
          .foregroundStyle(theme.brandActionBackground)
          .frame(width: 22, height: 22)
          .frame(width: 44, height: 44)
          .background(theme.brandActionBackground.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 10))
          .overlay {
            RoundedRectangle(cornerRadius: 10)
              .stroke(theme.brandControlBorder, lineWidth: 1)
          }
          // Inset rather than pushed past the edge, so nothing clips it.
          .overlay(alignment: .topTrailing) {
            if action.showsBadge {
              BrandBadgeDot()
                .padding(5)
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

/// A section's title, and a line on what it holds.
struct BrandPageHero: View {
  let title: String
  var subtitle: String?

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 34, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .designLineHeight(fontSize: 34)
      if let subtitle {
        Text(subtitle)
          .font(.system(size: 15))
          .foregroundStyle(theme.brandSecondaryText)
          .fixedSize(horizontal: false, vertical: true)
          .designLineHeight(fontSize: 15)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Controls

/// The design's switch. Its thumb sits right when on, in either language, as
/// drawn; the caller decides what a tap does, since some switches stand for a
/// permission only the system can grant.
struct BrandToggle: View {
  let isOn: Bool
  var isEnabled = true
  let action: () -> Void

  var body: some View {
    Button {
      action()
    } label: {
      Image(decorative: isOn ? "brand-toggle-on" : "brand-toggle-off", bundle: .module)
        .resizable()
        .frame(width: 48, height: 28)
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .opacity(isEnabled ? 1 : 0.4)
  }
}

/// A row of options side by side, the chosen one outlined in cyan. The others
/// keep a violet outline, or, where `outlinesUnselected` is false, just their
/// muted name.
struct BrandOptionPicker<Option: Hashable>: View {
  let options: [Option]
  let selection: Option
  let title: (Option) -> String
  var outlinesUnselected = true
  let select: (Option) -> Void

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    HStack(spacing: 8) {
      ForEach(options, id: \.self) { option in
        Button {
          select(option)
        } label: {
          optionLabel(option, isSelected: option == selection)
        }
        .buttonStyle(.plain)
        .accessibilitySelected(option == selection)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 52)
  }

  func optionLabel(_ option: Option, isSelected: Bool) -> some View {
    Text(title(option))
      .font(.system(size: 14))
      .foregroundStyle(
        isSelected ? theme.brandActionBackground : (outlinesUnselected ? theme.onDarkFill : theme.brandMutedText)
      )
      .multilineTextAlignment(.center)
      .lineLimit(2)
      .minimumScaleFactor(0.8)
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay {
        if isSelected || outlinesUnselected {
          RoundedRectangle(cornerRadius: 10)
            .stroke(isSelected ? theme.brandActionBackground : theme.brandOptionBorder, lineWidth: 1)
        }
      }
      .tappableFrame()
  }
}

extension View {
  /// Marks a control as selected for assistive technology.
  ///
  /// The trait is only ever *added*: never hand `accessibilityAddTraits` an
  /// empty `AccessibilityTraits` (`[]`, or `AccessibilityTraits()`). On
  /// Android, SkipFuseUI declares `init() { self = [] }`, and `[]` routes
  /// through `SetAlgebra`'s default array-literal init straight back into
  /// `init()` — the recursion overflows the stack and kills the process
  /// before the screen ever draws. iOS is unaffected, so the crash only
  /// shows up on device.
  @ViewBuilder
  func accessibilitySelected(_ isSelected: Bool) -> some View {
    if isSelected {
      self.accessibilityAddTraits(.isSelected)
    } else {
      self
    }
  }
}

/// The rule between a card's rows.
struct BrandRule: View {
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Rectangle()
      .fill(theme.brandControlBorder)
      .frame(height: 1)
  }
}

/// A row's "more this way": pointing left in Hebrew, right in English.
struct BrandForwardChevron: View {
  @Environment(\.layoutDirection) var layoutDirection
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Image("brand-chevron-forward", bundle: .module)
      .renderingMode(.template)
      .resizable()
      .foregroundStyle(theme.brandActionBackground)
      .frame(width: 24, height: 24)
      .scaleEffect(x: layoutDirection == .rightToLeft ? -1 : 1, y: 1)
      .accessibilityHidden(true)
  }
}

/// The dot that says news is waiting behind a control: new lessons.
struct BrandBadgeDot: View {
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Circle()
      .fill(theme.danger)
      .frame(width: 9, height: 9)
      .accessibilityHidden(true)
  }
}
