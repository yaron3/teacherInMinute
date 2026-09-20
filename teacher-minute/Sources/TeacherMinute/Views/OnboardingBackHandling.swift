//
//  OnboardingBackHandling.swift
//  teacher-minute
//
//  Back navigation for the onboarding steps.
//

import SwiftUI

/// Which onboarding step owns the back gesture, and what back should do there.
///
/// Onboarding steps sit on the router's path, so back means "one step back".
/// The first step is the exception: popping it leaves onboarding for the
/// sign-in screen, and the account is still signed in at that point — so that
/// step asks before it undoes the sign-in rather than dropping the user on a
/// login screen while logged in.
///
/// Android's system back is routed here too, through `MainActivity`. The
/// handlers are a stack because pushing a screen composes the arriving screen's
/// `onAppear` before the leaving screen's `onDisappear`, so the newcomer must
/// not be unregistered by the step it just replaced.
@MainActor
final class OnboardingBackCoordinator {
    static let shared = OnboardingBackCoordinator()

    private init() {}

    private struct Registration {
        let id: UUID
        let handler: () -> Void
    }

    private var registrations: [Registration] = []

    func register(id: UUID, handler: @escaping () -> Void) {
        registrations.removeAll { $0.id == id }
        registrations.append(Registration(id: id, handler: handler))
        updatePlatformHandling()
    }

    func unregister(id: UUID) {
        registrations.removeAll { $0.id == id }
        updatePlatformHandling()
    }

    /// Runs the newest handler, which is the step actually on screen.
    func handleBack() {
        registrations.last?.handler()
    }

    private func updatePlatformHandling() {
#if os(Android)
        AndroidBackNavigationBridge.setOnboardingBackHandling(!registrations.isEmpty)
#endif
    }
}

/// What `MainActivity` calls when the system back button is pressed during
/// onboarding.
/* SKIP @bridge */public final class OnboardingBackBridge : Sendable {
    /* SKIP @bridge */public static let shared = OnboardingBackBridge()

    private init() {
    }

    /* SKIP @bridge */@MainActor public func handleBack() {
        OnboardingBackCoordinator.shared.handleBack()
    }
}

extension View {
    /// Gives an onboarding step a back button that walks the flow backwards,
    /// and takes over the Android system back button while it is on screen.
    ///
    /// - Parameter isActive: `false` leaves the screen's back behaviour alone,
    ///   for the steps that double as an editing screen reached from elsewhere.
    func onboardingBackHandling(
        viewModel: any OnboardingBackViewModeling,
        isActive: Bool = true
    ) -> some View {
        modifier(OnboardingBackHandlingModifier(viewModel: viewModel, isActive: isActive))
    }
}

struct OnboardingBackHandlingModifier: ViewModifier {
    let viewModel: any OnboardingBackViewModeling
    let isActive: Bool
    @Environment(\.appRouter) var router
    @Environment(\.colorScheme) var colorScheme
    @State var id = UUID()
    @State var isConfirmingSignOut = false

    var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

    func body(content: Content) -> some View {
        content
            // The step draws its own back button so that both platforms go
            // through the same decision — a system back item would pop straight
            // out of onboarding without asking.
            .navigationBarBackButtonHidden(isActive)
            .toolbar {
                if isActive {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            handleBack()
                        } label: {
                            // "chevron.left", not "chevron.backward": the
                            // Android icon table knows the former and falls
                            // back to a filled dot for the latter. It renders
                            // the same way round as every other chevron in the
                            // app — PlatformIcon's right-to-left mirroring does
                            // not fire on Android, which is app-wide and not
                            // this screen's to special-case.
                            PlatformIcon(
                                systemName: "chevron.left",
                                size: 17,
                                weight: .semibold,
                                color: theme.primaryText
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .appDialog(
                viewModel.onboardingBackTitle,
                isPresented: $isConfirmingSignOut,
                message: viewModel.onboardingBackMessage,
                actions: [
                    AppDialogAction(viewModel.onboardingBackCancelLabel, kind: .cancel),
                    AppDialogAction(viewModel.onboardingBackConfirmLabel, kind: .destructive) {
                        signOutAndReturnToSignIn()
                    }
                ]
            )
            .onAppear {
                guard isActive else { return }
                OnboardingBackCoordinator.shared.register(id: id) {
                    handleBack()
                }
            }
            .onDisappear {
                OnboardingBackCoordinator.shared.unregister(id: id)
            }
    }

    /// One step back, or the question, when there is no step left to go back to.
    func handleBack() {
        if router.path.count > 1 {
            router.pop()
        } else {
            isConfirmingSignOut = true
        }
    }

    func signOutAndReturnToSignIn() {
        do {
            try AuthService().signOut()
        } catch {
            logger.error("[Onboarding] sign out from back navigation failed: \(error)")
        }
        router.signOut()
    }
}
