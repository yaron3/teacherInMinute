import SwiftUI

extension View {
  /// The icons the status and navigation bars draw over this screen: dark
  /// ones over a light ground, light ones over a dark one. When the screen
  /// goes, so does its request: the screen under it decides again, or else
  /// the app's colour scheme.
  ///
  /// Android only. iOS already reads the screen under its status bar and
  /// home indicator.
  func systemBarIcons(darkStatusBar: Bool, darkNavigationBar: Bool) -> some View {
    modifier(SystemBarIconsModifier(darkStatusBar: darkStatusBar, darkNavigationBar: darkNavigationBar))
  }
}

struct SystemBarIconsModifier: ViewModifier {
  let darkStatusBar: Bool
  let darkNavigationBar: Bool
  /// Whose request it is, so that only this screen withdraws it.
  @State var owner = UUID().uuidString

  func body(content: Content) -> some View {
#if os(Android)
    content
      .onAppear {
        apply()
      }
      .onChange(of: darkStatusBar) { _, _ in
        apply()
      }
      .onChange(of: darkNavigationBar) { _, _ in
        apply()
      }
      .onDisappear {
        AndroidSystemBarsBridge.followTheme(owner: owner)
      }
#else
    content
#endif
  }

#if os(Android)
  private func apply() {
    AndroidSystemBarsBridge.setDarkIcons(owner: owner, statusBar: darkStatusBar, navigationBar: darkNavigationBar)
  }
#endif
}
