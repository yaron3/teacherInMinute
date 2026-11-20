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
/// The first step is the exception: behind it are the welcome and sign-in
/// screens, and the account is signed in by then, so back never goes there.
/// That step has no back button, and Android's system back sends the app to
/// the background, as it does on the home tabs.
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
    /// Hands the Android system back button to this view while it is on
    /// screen. For an overlay drawn over a screen: back otherwise skips it and
    /// acts on what is beneath — on the tabs, sending the app to the
    /// background with the overlay still up.
    func onSystemBack(perform action: @escaping () -> Void) -> some View {
        modifier(SystemBackModifier(action: action))
    }
}

struct SystemBackModifier: ViewModifier {
    let action: () -> Void
    @State var id = UUID()

    func body(content: Content) -> some View {
        content
            .onAppear {
                OnboardingBackCoordinator.shared.register(id: id) { action() }
            }
            .onDisappear {
                OnboardingBackCoordinator.shared.unregister(id: id)
            }
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

    var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

    func body(content: Content) -> some View {
        content
            // The step draws its own back button so that both platforms go
            // through the same decision — a system back item would pop the
            // first step straight back to the sign-in screens.
            .navigationBarBackButtonHidden(isActive)
            .toolbar {
                if isActive && router.canStepBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            trackTap("onboarding_back")
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

    /// One step back. On the first step there is none: the sign-in screens
    /// behind it are not a way back for a signed-in account, so Android's
    /// system back leaves the app in the background on this step.
    func handleBack() {
        if router.canStepBack {
            router.pop()
        } else {
#if os(Android)
            AndroidBackNavigationBridge.moveAppToBack()
#endif
        }
    }
}
