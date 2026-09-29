import SwiftUI

extension View {
  /// Says which app an account belongs to when sign-in or launch has just
  /// turned it away (`AppRouter.otherAppAccountRole`), on the signed-out
  /// screen the app returned to. At launch that screen is still under the
  /// splash, so the notice appears as the splash fades.
  func otherAppAccountNotice() -> some View {
    modifier(OtherAppAccountNoticeModifier())
  }
}

struct OtherAppAccountNoticeModifier: ViewModifier {
  @State var viewModel = WelcomeViewModel()
  @Environment(\.appRouter) var router
  @Environment(\.openURL) var openURL

  func body(content: Content) -> some View {
    content
      .appDialog(
        notice?.title ?? "",
        isPresented: isPresented,
        message: notice?.message,
        actions: actions
      )
  }

  private var notice: OtherAppNotice? {
    router.otherAppAccountRole.map { viewModel.otherAppNotice(for: $0) }
  }

  private var isPresented: Binding<Bool> {
    Binding(
      get: { router.otherAppAccountRole != nil },
      set: { if !$0 { router.otherAppAccountRole = nil } }
    )
  }

  private var actions: [AppDialogAction] {
    guard let notice, let download = notice.download else {
      return [AppDialogAction(viewModel.okLabel)]
    }
    return [
      AppDialogAction(download.label) {
        viewModel.downloadTapped(for: notice)
        openURL(download.url)
      },
      AppDialogAction(viewModel.notNowLabel, kind: .cancel),
    ]
  }
}
