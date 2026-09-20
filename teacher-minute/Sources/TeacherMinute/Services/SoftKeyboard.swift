//
//  SoftKeyboard.swift
//  teacher-minute
//
//  Putting the system keyboard away, on both platforms.
//

import SwiftUI

enum SoftKeyboard {
    /// Dismisses the system keyboard.
    ///
    /// Clearing a `@FocusState` is enough on iOS, but not on Android: SkipUI's
    /// `.focused(_:)` requests focus when the binding turns true and does
    /// nothing at all when it turns false, so the IME stays up and whatever the
    /// app shows in the keyboard's place stacks on top of it. Call this
    /// alongside clearing the focus state whenever the keyboard has to go.
    static func dismiss() {
#if os(Android)
        AndroidKeyboardBridge.hideSoftKeyboard()
#elseif canImport(UIKit)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
#endif
    }

    /// Whether the keyboard is on screen.
    ///
    /// Android only, and reported as `true` elsewhere: the callers are watching
    /// for a keyboard that Skip's navigation took away behind SwiftUI's back,
    /// which is not a thing that happens on iOS, and `true` keeps them from
    /// looping there.
    static var isVisible: Bool {
#if os(Android)
        return AndroidKeyboardBridge.isSoftKeyboardVisible()
#else
        return true
#endif
    }

    /// Whether `isVisible` is worth believing on this device.
    ///
    /// Below Android 11 the system cannot say whether the keyboard is up — not
    /// for a window that draws edge to edge, anyway — so a caller that acts on
    /// `isVisible` there acts on a guess. False means: do not watch, do not
    /// correct, leave the keyboard alone.
    static var isVisibilityObservable: Bool {
#if os(Android)
        return AndroidKeyboardBridge.canReportSoftKeyboardVisibility()
#else
        return true
#endif
    }

    /// Asks for the keyboard for the field that already holds focus.
    ///
    /// Focus is what raises the keyboard normally, so this is only for the case
    /// where the field is still focused and the keyboard was taken anyway.
    static func show() {
#if os(Android)
        AndroidKeyboardBridge.showSoftKeyboard()
#endif
    }
}
