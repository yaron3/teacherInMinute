//
//  AppDialog.swift
//  teacher-minute
//
//  In-app replacement for SwiftUI's `.alert`.
//
//  `.alert` and `.confirmationDialog` are UIKit-backed, and UIKit decides their
//  layout direction from the process's `AppleLanguages` — which iOS reads once
//  at launch. The in-app language switch writes `AppleLanguages`, but it cannot
//  retroactively flip the running process, so a user reading Hebrew on an
//  English device gets left-aligned dialogs until the app is relaunched. The
//  root view's `layoutDirection` environment does not reach them either,
//  because they are presented outside that hierarchy.
//
//  Drawing the dialog inside the view tree keeps it in the app's own
//  environment, so direction follows the in-app language with no relaunch.
//

import SwiftUI

/// One button in an `appDialog`.
struct AppDialogAction {
    /// Shown only when a caller passes no actions at all, so the dialog can
    /// still be dismissed. No call site relies on it today; it exists so an
    /// empty array can never trap the user in an undismissable dialog.
    static var dismissFallback: AppDialogAction {
        AppDialogAction(LocalizationSupport.localized("OK"), kind: .primary)
    }

    /// Drives the button's appearance, and nothing else — dismissal is handled
    /// by the dialog for every kind, so `handler` only carries side effects.
    enum Kind {
        /// Filled accent button. The action the dialog is steering toward.
        case primary
        /// Plain text button for backing out.
        case cancel
        /// Filled danger button for irreversible actions.
        case destructive
    }

    let title: String
    let kind: Kind
    let handler: () -> Void

    init(_ title: String, kind: Kind = .primary, handler: @escaping () -> Void = {}) {
        self.title = title
        self.kind = kind
        self.handler = handler
    }
}

struct AppDialogView: View {
    let title: String
    let message: String?
    let actions: [AppDialogAction]
    let onDismiss: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

    /// Read from the in-app language rather than `@Environment`. A dialog shown
    /// through `fullScreenCover` is a separate presentation context and does not
    /// inherit `layoutDirection` from the presenting view, so an inherited value
    /// would silently fall back to LTR and left-align Hebrew.
    var layoutDirection: LayoutDirection {
        LocalizationSupport.layoutDirection
    }

    /// Text hugs the reading edge, which is what makes Hebrew right-aligned.
    var textAlignment: HorizontalAlignment {
        layoutDirection == .rightToLeft ? .trailing : .leading
    }

    var frameAlignment: Alignment {
        layoutDirection == .rightToLeft ? .trailing : .leading
    }

    var body: some View {
        ZStack {
            theme.scrim.opacity(0.35)
                .ignoresSafeArea()

            VStack(alignment: textAlignment, spacing: 14) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(theme.primaryText)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)

                if let message, !message.isEmpty {
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: frameAlignment)
                }

                VStack(spacing: 10) {
                    ForEach(0..<actions.count, id: \.self) { index in
                        actionButton(actions[index])
                    }
                }
                .padding(.top, 2)
            }
            .padding(20)
            .background(theme.screenBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 32)
        }
        // Pushed down so nested text and controls flip too, not just the
        // alignments computed above.
        .environment(\.layoutDirection, layoutDirection)
        .environment(\.locale, LocalizationSupport.currentLocale)
    }

    @ViewBuilder
    func actionButton(_ action: AppDialogAction) -> some View {
        Button {
            // Dismiss first so a handler that presents something else is not
            // fighting this dialog for the screen.
            onDismiss()
            action.handler()
        } label: {
            Text(action.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(foreground(for: action.kind))
                .frame(maxWidth: .infinity)
                .frame(height: action.kind == .cancel ? 40 : 46)
                .background(background(for: action.kind))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    func foreground(for kind: AppDialogAction.Kind) -> Color {
        switch kind {
        case .primary, .destructive: return theme.onAccentText
        case .cancel: return theme.secondaryText
        }
    }

    func background(for kind: AppDialogAction.Kind) -> Color {
        switch kind {
        case .primary: return theme.accent
        case .destructive: return theme.danger
        case .cancel: return Color.clear
        }
    }
}

extension View {
    /// Presents an in-app dialog that honours the app's own layout direction.
    /// Drop-in stand-in for `.alert(_:isPresented:actions:message:)`.
    ///
    /// - Parameter coversScreen: pass `true` when attaching to a small view. An
    ///   overlay is laid out inside the bounds of the view it modifies, so a
    ///   dialog attached to, say, a 44pt button would be crushed into it; a
    ///   full-screen presentation escapes those bounds. Leave `false` when
    ///   attaching at a screen root, where the overlay already fills the screen
    ///   and avoids stacking another presentation onto the view.
    func appDialog(
        _ title: String,
        isPresented: Binding<Bool>,
        message: String? = nil,
        actions: [AppDialogAction],
        coversScreen: Bool = false
    ) -> some View {
        let dialog = AppDialogView(
            title: title,
            message: message,
            actions: actions.isEmpty ? [AppDialogAction.dismissFallback] : actions,
            onDismiss: { isPresented.wrappedValue = false }
        )
#if os(Android)
        // Skip marks `presentationBackground` unavailable, so a cover here could
        // not be made transparent. Every Android call site attaches at a screen
        // root, where the overlay already spans the screen.
        return overlay {
            if isPresented.wrappedValue {
                dialog
            }
        }
#else
        return overlay {
            if isPresented.wrappedValue && !coversScreen {
                dialog
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { coversScreen && isPresented.wrappedValue },
            set: { if !$0 { isPresented.wrappedValue = false } }
        )) {
            dialog.presentationBackground(.clear)
        }
#endif
    }
}
