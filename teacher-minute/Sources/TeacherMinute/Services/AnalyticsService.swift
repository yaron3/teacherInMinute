//
//  AnalyticsService.swift
//  teacher-minute
//
//  Thin wrapper around Firebase Analytics + Crashlytics so the rest of the
//  app can log events without sprinkling `#if os(Android)` everywhere.
//

import Foundation
import SwiftUI

#if !os(Android)
import FirebaseAnalytics
import FirebaseCrashlytics
#else
import SkipFirebaseAnalytics
import SkipFirebaseCrashlytics
#endif

/// Centralised event names used across the app. Keeping them here avoids
/// typos and makes it easier to audit what we're recording.
enum AnalyticsEvent {
    // Auth
    static let signUpStart       = "sign_up_start"
    static let signUpSuccess     = "sign_up_success"
    static let signUpFailure     = "sign_up_failure"
    static let loginStart        = "login_start"
    static let loginSuccess      = "login_success"
    static let loginFailure      = "login_failure"
    static let logout            = "logout"
    static let passwordResetSent = "password_reset_sent"
    static let phoneVerifySent   = "phone_verify_sent"
    static let phoneVerified     = "phone_verified"

    // Role / onboarding
    static let roleSelected            = "role_selected"
    static let profileCompleted        = "profile_completed"
    static let teacherSubjectsSaved    = "teacher_subjects_saved"
    static let teacherIdentityUploaded = "teacher_identity_uploaded"

    // Student flow
    static let askTeacherSubmitted = "ask_teacher_submitted"
    static let askTeacherCancelled = "ask_teacher_cancelled"
    static let askTeacherMatched   = "ask_teacher_matched"
    static let askTeacherNoMatch   = "ask_teacher_no_match"
    static let askTeacherFailed    = "ask_teacher_failed"

    // Teacher flow
    static let teacherAcceptingToggled = "teacher_accepting_toggled"
    static let teacherInviteAccepted   = "teacher_invite_accepted"
    static let teacherInviteDeclined   = "teacher_invite_declined"

    // Chat / session
    static let chatMessageSent  = "chat_message_sent"
    static let chatPhotoSent    = "chat_photo_sent"
    static let chatSessionEnded = "chat_session_ended"

    // Purchase
    static let beginCheckout          = "begin_checkout"  // also a GA4 standard event
    static let checkoutFailed         = "checkout_failed"
    static let checkoutOpened         = "checkout_opened"
    static let purchase               = "purchase"        // GA4 standard event
    static let purchaseCancelled      = "purchase_cancelled"
    static let purchaseFailed         = "purchase_failed"
    static let purchasePending        = "purchase_pending"

    // Settings / misc
    static let languageChanged        = "language_changed"
    static let permissionRequest      = "permission_request"
    static let permissionGranted      = "permission_granted"
    static let permissionDenied       = "permission_denied"
    static let notificationOpened     = "notification_opened"
    static let contactSupportOpened   = "contact_support_opened"
    static let contactSupportPreview  = "contact_support_preview"
    static let contactSupportCancelled = "contact_support_cancelled"
    static let contactSupportSubmitted = "contact_support_submitted"
    static let contactSupportFailed    = "contact_support_failed"

    // Backend errors
    static let firestorePermissionDenied = "firestore_permission_denied"
}

/// Names for `screen_view` tracking. Used as the `screen_name` parameter.
enum AnalyticsScreen {
    static let welcome           = "welcome"
    static let login             = "login"
    static let createAccount     = "create_account"
    static let resetPassword     = "reset_password"
    static let verifyPhone       = "verify_phone"
    static let chooseRole        = "choose_role"
    static let completeProfile   = "complete_profile"
    static let teacherIdentity   = "teacher_identity_verification"
    static let teacherSubjects   = "teacher_subjects"
    static let permissionsSetup  = "permissions_setup"

    static let studentHome           = "student_home"
    static let teacherDashboard      = "teacher_dashboard"
    static let studentLessonHistory  = "student_lesson_history"
    static let teacherLessonHistory  = "teacher_lesson_history"
    static let profile               = "profile"
    static let settings              = "settings"
    static let notificationMessages  = "notification_messages"
    static let chatSession           = "chat_session"
    static let askTeacherSheet       = "ask_teacher_sheet"
    static let about                 = "about_web"
    static let connectionSetup       = "connection_setup"
    static let whiteboard            = "whiteboard"
}

@MainActor
final class AnalyticsService {
    static let shared = AnalyticsService()

    private init() {}

    // MARK: - Setup

    /// Called after `FirebaseApp.configure()`. Currently Analytics and
    /// Crashlytics are enabled by default once the products are linked, but
    /// we expose this so we have one place to wire it up.
    func start() {
        Analytics.setAnalyticsCollectionEnabled(true)
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
        logger.info("[Analytics] started")
    }

    func setUser(uid: String?, role: String? = nil) {
        Analytics.setUserID(uid)
        Crashlytics.crashlytics().setUserID(uid ?? "")
        if let role {
            setRole(role)
        }
    }

    func setRole(_ role: String) {
        Analytics.setUserProperty(role, forName: "user_role")
        Crashlytics.crashlytics().setCustomValue(role, forKey: "user_role")
    }

    // MARK: - Events

    func logEvent(_ name: String, parameters: [String: Any]? = nil) {
        let sanitized = AnalyticsService.sanitize(parameters)
        Analytics.logEvent(name, parameters: sanitized)
        let breadcrumb = sanitized?.isEmpty == false ? "\(name) \(sanitized!)" : name
        Crashlytics.crashlytics().log(breadcrumb)
    }

    func logScreen(_ screen: String, screenClass: String? = nil) {
        var params: [String: Any] = [
            AnalyticsParameterScreenName: screen
        ]
        if let screenClass {
            params[AnalyticsParameterScreenClass] = screenClass
        }
        Analytics.logEvent(AnalyticsEventScreenView, parameters: params)
        Crashlytics.crashlytics().log("screen_view \(screen)")
    }

    // MARK: - Purchase helpers

    /// Logs `begin_checkout` with the pricing option metadata.
    func logBeginCheckout(option: PricingOption) {
        let value = Double(option.priceCents) / 100.0
        let params: [String: Any] = [
            AnalyticsParameterItemID: option.id,
            AnalyticsParameterItemName: option.name,
            AnalyticsParameterItemCategory: option.type.rawValue,
            AnalyticsParameterPrice: value,
            AnalyticsParameterValue: value,
            AnalyticsParameterCurrency: option.currency,
            "minutes_granted": option.minutesGranted ?? 0,
            "purchase_sku": option.purchaseSKU ?? ""
        ]
        logEvent(AnalyticsEvent.beginCheckout, parameters: params)
    }

    /// Logs the GA4 `purchase` event after a successful payment. `option`
    /// describes what was bought; `transactionID` is the Stripe / PayPal
    /// session or order id we got back from the return URL.
    func logPurchase(option: PricingOption?, transactionID: String?) {
        var params: [String: Any] = [:]
        if let option {
            let value = Double(option.priceCents) / 100.0
            params[AnalyticsParameterItemID] = option.id
            params[AnalyticsParameterItemName] = option.name
            params[AnalyticsParameterItemCategory] = option.type.rawValue
            params[AnalyticsParameterPrice] = value
            params[AnalyticsParameterValue] = value
            params[AnalyticsParameterCurrency] = option.currency
            params["minutes_granted"] = option.minutesGranted ?? 0
            params["purchase_sku"] = option.purchaseSKU ?? ""
        }
        if let transactionID, !transactionID.isEmpty {
            params[AnalyticsParameterTransactionID] = transactionID
        }
        logEvent(AnalyticsEvent.purchase, parameters: params)
    }

    func logPurchaseOutcome(_ event: String, option: PricingOption?, transactionID: String?, reason: String? = nil) {
        var params: [String: Any] = [:]
        if let option {
            params[AnalyticsParameterItemID] = option.id
            params[AnalyticsParameterItemName] = option.name
            params[AnalyticsParameterPrice] = Double(option.priceCents) / 100.0
            params[AnalyticsParameterCurrency] = option.currency
        }
        if let transactionID, !transactionID.isEmpty {
            params[AnalyticsParameterTransactionID] = transactionID
        }
        if let reason, !reason.isEmpty {
            params["reason"] = reason
        }
        logEvent(event, parameters: params)
    }

    // MARK: - Crashlytics

    func recordError(_ error: Error, context: String? = nil) {
        if let context {
            Crashlytics.crashlytics().log("error in \(context): \(error.localizedDescription)")
        }
        Crashlytics.crashlytics().record(error: error)
    }

    /// Emits a `firestore_permission_denied` analytics event when `error`
    /// looks like a Firestore permission failure. Safe to call on any
    /// error — non-matching errors are ignored. Cross-platform: matches
    /// both the iOS NSError domain/code and the message string used on
    /// Android (Skip) builds.
    func recordPermissionIfNeeded(_ error: Error, context: String) {
        let nsError = error as NSError
        let isFirestoreDomain = nsError.domain == "FIRFirestoreErrorDomain" && nsError.code == 7
        let message = error.localizedDescription.lowercased()
        let messageMatches = message.contains("permission_denied")
            || message.contains("missing or insufficient permissions")
            || message.contains("insufficient permissions")
        guard isFirestoreDomain || messageMatches else { return }
        logEvent(AnalyticsEvent.firestorePermissionDenied, parameters: [
            "context": context,
            "message": error.localizedDescription
        ])
    }

    func log(_ message: String) {
        Crashlytics.crashlytics().log(message)
    }

    // MARK: - Helpers

    /// Firebase Analytics on iOS only accepts `NSNumber` / `NSString` /
    /// boxed Swift primitives in the parameters dict. We do a defensive
    /// pass to coerce values into safe types and drop nil entries.
    private static func sanitize(_ parameters: [String: Any]?) -> [String: Any]? {
        guard let parameters else { return nil }
        var result: [String: Any] = [:]
        for (key, value) in parameters {
            switch value {
            case let v as String:
                result[key] = v
            case let v as Bool:
                result[key] = v ? 1 : 0
            case let v as Int:
                result[key] = v
            case let v as Int64:
                result[key] = v
            case let v as Double:
                result[key] = v
            case let v as Float:
                result[key] = Double(v)
            default:
                result[key] = "\(value)"
            }
        }
        return result
    }
}

// MARK: - SwiftUI helpers

 struct TrackScreenModifier: ViewModifier {
    let screen: String

    func body(content: Content) -> some View {
        content.onAppear {
            AnalyticsService.shared.logScreen(screen)
        }
    }
}

extension View {
    /// Records a `screen_view` Analytics event the first time the view
    /// appears. Use one of the `AnalyticsScreen` constants for the name.
    func trackScreen(_ screen: String) -> some View {
        modifier(TrackScreenModifier(screen: screen))
    }
}
