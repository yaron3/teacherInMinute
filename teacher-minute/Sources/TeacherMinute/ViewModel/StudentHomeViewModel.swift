//
//  StudentHomeViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
import Observation
import Foundation

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

// MARK: - Search State

enum StudentSearchState {
  case idle
  case searching(questionId: String)
  case matched(questionId: String, liveKitRoom: String, liveKitToken: String)
  case noMatch
  case error(String)
}

// MARK: - Supporting Models

/// Pricing tier type. Firestore stores the raw string in the `type` field.
enum PricingType: String {
  case payAsYouGo       = "pay_as_you_go"
  case unlimitedWeek    = "unlimited_week"
  case unlimitedMonth   = "unlimited_month"
  case unlimitedYear    = "unlimited_year"

  var billingPeriodText: String? {
    switch self {
    case .payAsYouGo:     return nil
    case .unlimitedWeek:  return "per week"
    case .unlimitedMonth: return "per month"
    case .unlimitedYear:  return "per year"
    }
  }
}

/// A pricing tier loaded from Firestore (`pricing` collection).
///
/// Firestore document fields:
///   - `name` (String)
///   - `priceCents` (Int) — price in minor currency units
///   - `currency` (String) — ISO code, defaults to "USD"
///   - `type` (String) — one of `PricingType` raw values
///   - `description` (String)
///   - `isHighlighted` (Bool)
///   - `sortOrder` (Int)
///   - `purchaseSKU` (String, optional) — store / IAP product identifier
///   - `minutes` (Int) — number of lesson minutes granted by the package
///
/// The document ID is exposed as `id` and is the key recorded on the user
/// document (e.g. `users/{uid}.purchases[]`) when the tier is purchased.
struct PricingOption: Identifiable {
  let id: String
  let name: String
  let priceCents: Int
  let currency: String
  let type: PricingType
  let description: String
  let isHighlighted: Bool
  let sortOrder: Int
  let purchaseSKU: String?
  let minutesGranted: Int?

  var priceText: String {
    LessonFormatting.currencyText(cents: priceCents, currencyCode: currency)
  }

  var minutesText: String? {
    guard let minutes = minutesGranted, minutes > 0 else { return nil }
    return String(format: LocalizationSupport.localized("%d min"), minutes)
  }
}

struct RecentLesson: Identifiable {
  let id = UUID()
  let title: String
  let teacher: String
  let teacherImageURL: String
  let time: String
  let duration: String
  /// What the student scored this lesson, 1–5, or 0 when they never rated it.
  /// Drives the stars on the "Last Lesson" card, which used to be five filled
  /// stars regardless of the score.
  var rating: Int = 0

  var hasRating: Bool { rating > 0 }
}

// MARK: - Coupon State

enum CouponRedemptionState: Equatable {
  case idle
  case loading
  case success(minutesAdded: Int)
  case alreadyActivated(date: String)
  case invalid
  case error(String)
}

/// What a completed purchase granted, for the confirmation shown afterwards.
/// Built from the pricing option the buyer chose rather than re-read from the
/// server, so the wallet and redirect flows can describe the purchase
/// identically.
struct PurchaseSummary {
  /// Distinct per purchase, so buying the same package twice still re-presents
  /// the confirmation when observed via `onChange`.
  let id = UUID().uuidString
  let packageName: String
  let priceText: String
  let minutesText: String?

  init(option: PricingOption) {
    packageName = option.name
    priceText = option.priceText
    minutesText = option.minutesText
  }
}

// MARK: - ViewModel Protocol

@MainActor
protocol StudentHomeViewModeling: AnyObject {
  var name: String { get set }
  var searchState: StudentSearchState { get set }
  var activeQuestionText: String { get set }
  var activeConversationType: String { get set }
  var selectedPricePerMinuteCents: Int { get set }
  var questionId: String? { get set }
  var pricingOptions: [PricingOption] { get }
  var availablePaymentMethods: [PaymentMethod] { get }
  var savedPayPalEmail: String? { get set }
  var recentLessons: [RecentLesson] { get set }
  var onlineTeachers: [OnlineTeacher] { get set }
  var subjects: [StudentSubject] { get }
  var pricePerMinuteText: String { get }
  var averageConnectText: String { get }
  var connectPromiseText: String { get }
  var appMainIssueText: String { get }
  var connectStepTitle: String { get }
  var averageResponseText: String { get }
  var registeredTeacherCountText: String { get }
  var totalTimeLearnedText: String { get }
  var totalPurchasedText: String { get }
  var lessonCount: Int { get }
  var hasUnreadMessages: Bool { get set }
  var profileImageURL: String { get set }
  var remainingMinutes: Int { get set }
  var checkoutURL: URL? { get set }
  var isStartingCheckout: Bool { get set }
  var isPreparingCheckout: Bool { get set }
  var checkoutPricingOptionID: String? { get set }
  var isAwaitingPaymentReturn: Bool { get set }
  var couponCode: String { get set }
  var couponState: CouponRedemptionState { get set }
  var purchaseSummary: PurchaseSummary? { get set }

  func askTeacher(topic: String, text: String, photoUrls: [String], conversationType: String) async
  func cancelSearch() async
  func resetSearch()
  func selectTier(_ option: PricingOption)
  func preparePaymentOptions() async
  func checkout(_ option: PricingOption, method: PaymentMethod) async
  func consumeCheckoutURL()
  func checkoutDidOpen()
  func resumeCheckoutSpinner()
  func handlePaymentReturn(_ result: PaymentReturnResult) async
  func handleCheckoutReturnWithoutResult() async -> Bool
  func viewAllLessons()
  func loadProfileIfNeeded() async
  func refresh() async
  func refreshAfterLessonEnded() async
  func refreshUnreadMessages() async
  func chatInitialDetails(questionId: String?) -> ChatSessionDetails
  func redeemCoupon() async
  func resetCouponState()
  func consumePurchaseSummary()
}

// MARK: - Default Localized Strings

extension StudentHomeViewModeling {

  // MARK: Dialog & button labels
  var askATeacherSheetTitle: String { LocalizationSupport.localized("Ask a Teacher") }
  var lowBalanceAlertTitle: String { LocalizationSupport.localized("Low Balance") }
  var okLabel: String { LocalizationSupport.localized("OK") }
  var purchaseCompleteTitle: String { LocalizationSupport.localized("Purchase complete") }
  var openingCheckoutText: String { LocalizationSupport.localized("Opening secure checkout\u{2026}") }
  var paymentFallbackTitle: String { LocalizationSupport.localized("Payment") }
  var meetLabel: String { LocalizationSupport.localized("Meet") }
  var redeemLabel: String { LocalizationSupport.localized("Redeem") }
  var couponPlaceholder: String { LocalizationSupport.localized("Have a code?") }
  var chatTeacherTitle: String { LocalizationSupport.localized("Teacher") }
  var perMinuteSuffix: String { LocalizationSupport.localized("/min") }

  // MARK: Section headers & captions
  var availableSubjectsTitle: String { LocalizationSupport.localized("Available Subjects") }
  var teachersOnlineNowTitle: String { LocalizationSupport.localized("Teachers online now") }
  var teachersOnlineNowCaption: String { LocalizationSupport.localized("All") }
  var creditsTitle: String { LocalizationSupport.localized("Credits") }

  // MARK: Hero section
  var appDisplayName: String { LocalizationSupport.localized("Teacher in a Moment") }
  var minutesLabel: String { LocalizationSupport.localized("minutes") }
  var askQuestionNowLabel: String { LocalizationSupport.localized("Ask a question now") }

  // MARK: Overview cards
  var yourBalanceTitle: String { LocalizationSupport.localized("Your Balance") }
  var leftToLearnDetail: String { LocalizationSupport.localized("Left to learn") }
  var buyMoreLabel: String { LocalizationSupport.localized("Buy More +") }
  var lastLessonCardTitle: String { LocalizationSupport.localized("Last Lesson") }
  var noLessonsText: String { LocalizationSupport.localized("None yet") }
  var noLessonsSubtitle: String { LocalizationSupport.localized("Ask a teacher to start") }
  var noTeachersOnlineText: String { LocalizationSupport.localized("No teachers online right now") }

  // MARK: How it works
  var howItWorksTitle: String { LocalizationSupport.localized("How it works") }
  var howItWorksStep1Title: String { LocalizationSupport.localized("Ask a question") }
  var howItWorksStep1Subtitle: String { LocalizationSupport.localized("Describe the problem – text, image, or whiteboard drawing") }
  var howItWorksStep2Subtitle: String { LocalizationSupport.localized("The system finds an available teacher for your subject") }
  var howItWorksStep3Title: String { LocalizationSupport.localized("Live lesson") }
  var howItWorksStep3Subtitle: String { LocalizationSupport.localized("Chat, whiteboard, voice messages – real time") }
  var howItWorksStep4Title: String { LocalizationSupport.localized("Pay only for what you used") }
  var howItWorksStep4SubtitleFallback: String { LocalizationSupport.localized("Only billed minutes count") }

  // MARK: Stats strip
  var timeLearnedTitle: String { LocalizationSupport.localized("Time Learned") }
  var totalPurchasedTitle: String { LocalizationSupport.localized("Total Purchased") }

  // MARK: Ask card
  var askMathTeacherLabel: String { LocalizationSupport.localized("Ask a math teacher") }
  var perMinuteBillingLabel: String { LocalizationSupport.localized("Per-minute billing") }

  // MARK: Tips card
  var tipsTitle: String { LocalizationSupport.localized("Tips for faster matches") }
  var tip1Text: String { LocalizationSupport.localized("Upload a clear photo of your math problem") }
  var tip2Text: String { LocalizationSupport.localized("Specify the exact topic (e.g., \u{201C}Derivatives\u{201D})") }

  // MARK: Dynamic computed strings

  var studentDisplayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? LocalizationSupport.localized("Student") : trimmed
  }

  var greetingText: String {
    String(format: LocalizationSupport.localized("Hello, %@"), studentDisplayName)
  }

  /// Hebrew and English both read wrong as "1 teachers available now", and a
  /// single format string cannot carry both forms, so the singular gets its own
  /// string the way "1 teacher"/"%d teachers" already do.
  var onlineTeachersCountText: String {
    if onlineTeachers.count == 1 {
      return LocalizationSupport.localized("1 teacher available now")
    }
    return String(format: LocalizationSupport.localized("%d teachers available now"), onlineTeachers.count)
  }

  var remainingMinutesText: String {
    String(format: LocalizationSupport.localized("%d min remaining"), remainingMinutes)
  }

  var lowBalanceMessage: String {
    let format = LocalizationSupport.localized("You have %@ remaining. You need at least 2 minutes to ask a teacher. Please buy more minutes to continue.")
    return String(format: format, LessonFormatting.minutesText(remainingMinutes))
  }

  var couponAlertTitle: String {
    switch couponState {
    case .success: return LocalizationSupport.localized("Success")
    case .alreadyActivated: return LocalizationSupport.localized("Code Already Used")
    case .invalid: return LocalizationSupport.localized("Invalid Code")
    case .error: return LocalizationSupport.localized("Error")
    default: return ""
    }
  }

  var couponAlertMessage: String {
    switch couponState {
    case .success(let minutes):
      return String(format: LocalizationSupport.localized("Code applied! Added %d minutes."), minutes)
    case .alreadyActivated(let date):
      return String(format: LocalizationSupport.localized("This code was already activated on %@."), date)
    case .invalid:
      return LocalizationSupport.localized("This code is not valid.")
    case .error(let msg):
      return msg
    default:
      return ""
    }
  }

  var purchaseSummaryMessage: String {
    guard let summary = purchaseSummary else { return "" }
    let purchased = String(format: LocalizationSupport.localized("%@ purchased for %@."), summary.packageName, summary.priceText)
    guard let minutesText = summary.minutesText else { return purchased }
    let added = String(format: LocalizationSupport.localized("Added %@ to your balance."), minutesText)
    return purchased + "\n" + added
  }

  // MARK: Per-item text helpers

  func teacherCountText(for subject: StudentSubject) -> String {
    subject.teacherCount == 1
      ? LocalizationSupport.localized("1 teacher")
      : String(format: LocalizationSupport.localized("%d teachers"), subject.teacherCount)
  }

  func teacherAvailabilityText(for subject: StudentSubject) -> String {
    subject.hasTeachersOnline
      ? LocalizationSupport.localized("Teacher available now")
      : LocalizationSupport.localized("No one available now")
  }

  func localizedName(for option: PricingOption) -> String {
    LocalizationSupport.localized(option.name)
  }

  func localizedDescription(for option: PricingOption) -> String {
    LocalizationSupport.localized(option.description)
  }
}

// MARK: - ViewModel

@Observable
@MainActor
final class StudentHomeViewModel: StudentHomeViewModeling {

  var name = ""
  var searchState: StudentSearchState = .idle
  var activeQuestionText = ""
  var activeConversationType = "text"
  var selectedPricePerMinuteCents = 50
  var questionId: String?

  var pricingOptions: [PricingOption] = []
  var availablePaymentMethods: [PaymentMethod] = PaymentMethod.availableForCurrentPlatform
  var savedPayPalEmail: String?

  var recentLessons: [RecentLesson] = []
  var onlineTeachers: [OnlineTeacher] = []
  /// The subject grid: the Remote Config catalog joined with how many teachers
  /// are online for each subject right now.
  var subjects: [StudentSubject] = []
  /// "2₪ per minute • pay only for time used" — the rate comes from Remote
  /// Config, not a number written into the copy.
  var pricePerMinuteText = ""
  /// "90 sec avg to connect", measured by the backend. Empty until there is a
  /// measurement, so the view can leave the claim out entirely.
  var averageConnectText = ""
  /// "237 registered teachers", counted by the backend. Empty until the counter
  /// is seeded, so the view omits the caption rather than claiming zero.
  var registeredTeacherCountText = ""
  /// The hero line and the "how it works" step, both of which used to promise a
  /// fixed 90 seconds. They now quote the measured average, and fall back to
  /// wording that makes no numeric claim when there is nothing to quote.
  var appMainIssueText = LocalizationSupport.localized("Stuck? You will have a teacher immediately")
  var connectPromiseText = LocalizationSupport.localized("Help from a real teacher, exactly when you need it") 

  var connectStepTitle = LocalizationSupport.localized("A teacher connects quickly")
  /// The line on the ask-a-question sheet. Empty when nothing has been
  /// measured, so the sheet drops it instead of quoting a made-up figure.
  var averageResponseText = ""
  var totalTimeLearnedText = LessonFormatting.totalDurationText(lessons: [])
  var totalPurchasedText = LessonFormatting.minutesText(0)
  var lessonCount = 0
  var hasUnreadMessages = false
  var profileImageURL = ""
  var remainingMinutes = 0
  var checkoutURL: URL?
  var isStartingCheckout = false
  /// True from the moment checkout starts until the buyer is handed off to
  /// something they can see — the wallet sheet, or the browser. Distinct from
  /// `isStartingCheckout`, which stays true for the whole wallet payment and
  /// so would leave a spinner sitting behind the Apple Pay sheet.
  var isPreparingCheckout = false
  var checkoutPricingOptionID: String?
  var isAwaitingPaymentReturn = false
  var couponCode = ""
  var couponState: CouponRedemptionState = .idle
  var purchaseSummary: PurchaseSummary?

  private var pollingTask: Task<Void, Never>?
  private var onlineTeachersStore: OnlineTeachersStore?
  /// Subject keys (e.g. "math", "physics") enabled via Remote Config
  /// (`enable_<key>`). "math" is the only one on by default; every other
  /// subject stays hidden until its flag is explicitly turned on remotely.
  private var enabledSubjectKeys: Set<String> = ["math"]
  /// The subject catalog as published, kept so the grid can be rebuilt with new
  /// teacher counts whenever presence changes without re-reading Remote Config.
  private var subjectCatalog: [RemoteTeachingSubject] = []
  /// Normalized subject keys of every teacher currently online, one entry per
  /// teacher, so a subject's count is how many of these sets match it.
  private var onlineTeacherSubjectKeys: [Set<String>] = []
  /// The student's own currency, so the per-minute rate is quoted in it.
  private var currencyCode = LessonFormatting.defaultCurrencyCode
  private var didLoadProfile = false
  private var checkoutStartedRemainingMinutes = 0
  /// The option being bought. Unlike `checkoutPricingOptionID` this survives
  /// the end of `checkout(_:method:)`, because the redirect flows only learn
  /// the purchase succeeded once the buyer comes back from the browser.
  private var pendingPurchaseOption: PricingOption?
  /// Last-resort timer that takes the checkout spinner down if the browser
  /// hand-off never happened. See `checkoutDidOpen`.
  private var checkoutHandoffWatchdog: Task<Void, Never>?
  private var purchasedCurrencyCode = LessonFormatting.defaultCurrencyCode

  // MARK: - Actions

  func askTeacher(topic: String, text: String, photoUrls: [String] = [], conversationType: String = "text") async {
    guard case .idle = searchState else { return }
	logger.info("TeacherMinute askTeacher submit topic=\(topic) textLength=\(text.count)")
    activeConversationType = conversationType
    searchState = .searching(questionId: "")

    let hasOnlineTeacher = await TeacherAvailabilityStore.hasOnlineTeacher()
    if !hasOnlineTeacher {
      logger.info("TeacherMinute askTeacher aborted: no online teachers")
      searchState = .noMatch
      return
    }

    do {
      let result = try await FunctionsService.shared.createQuestion(
        topic: topic,
        text: text,
        photoUrls: photoUrls,
        conversationType: conversationType
      )
	  logger.info("TeacherMinute askTeacher created questionId=\(result.questionId)")
      activeQuestionText = text
      searchState = .searching(questionId: result.questionId)
      startPolling(questionId: result.questionId)
    } catch let err as FunctionsError {
      if case .serverError(_, let status) = err, status == "RESOURCE_EXHAUSTED" {
        logger.info("TeacherMinute askTeacher blocked: insufficient minutes")
        searchState = .error(LocalizationSupport.localized("Not enough time left. Please purchase more minutes."))
      } else {
        logger.error("TeacherMinute askTeacher failed error=\(err)")
        searchState = .error(err.localizedDescription)
      }
    } catch {
	  logger.error("TeacherMinute askTeacher failed error=\(error)")
      searchState = .error(error.localizedDescription)
    }
  }

  func cancelSearch() async {
    guard case .searching(let qid) = searchState else { return }
    pollingTask?.cancel()
    pollingTask = nil
    if !qid.isEmpty {
      try? await FunctionsService.shared.cancelQuestion(questionId: qid)
    }
    searchState = .idle
  }

  func resetSearch() {
    pollingTask?.cancel()
    pollingTask = nil
    searchState = .idle
  }

  func selectTier(_ option: PricingOption) {
    selectedPricePerMinuteCents = option.priceCents
  }

  /// Settles everything the payment picker needs before it is put on screen, so
  /// the buyer sees the finished list of methods rather than one that grows a
  /// row at a time. Deliberately leaves `isPreparingCheckout` set: the caller
  /// clears it once the picker is up, so the spinner hands straight over to the
  /// sheet with no bare frame in between.
  func preparePaymentOptions() async {
    isPreparingCheckout = true
    await loadPaymentMethods()
#if canImport(UIKit)
    if availablePaymentMethods.contains(.applePay) {
      ApplePayService.shared.warmUpPaymentButton()
    }
#endif
  }

  func checkout(_ option: PricingOption, method: PaymentMethod = .paypal) async {
    guard !isStartingCheckout else { return }
    logger.info("[PaymentReturn] checkout start pricingOptionID=\(option.id) method=\(method.rawValue)")
    isStartingCheckout = true
    isPreparingCheckout = true
    checkoutPricingOptionID = option.id
    checkoutStartedRemainingMinutes = remainingMinutes
    pendingPurchaseOption = option
    defer {
      isStartingCheckout = false
      checkoutPricingOptionID = nil
    }
    selectTier(option)

    // The wallets run the whole payment inside the awaited call below, so the
    // spinner covers everything from the tap to the charge being confirmed or
    // rejected — including the beat after the wallet sheet closes, while the
    // nonce is sent to the backend.
    if method == .applePay {
      await checkoutWithApplePay(option)
      isPreparingCheckout = false
      return
    }

    if method == .googlePay {
      await checkoutWithGooglePay(option)
      isPreparingCheckout = false
      return
    }

#if canImport(UIKit)
    if method == .savedPayPal {
      await checkoutWithSavedPayPal(option)
      isPreparingCheckout = false
      return
    }
#endif

    do {
      let result = try await FunctionsService.shared.createCheckoutSession(pricingOptionID: option.id, paymentMethod: method)
      checkoutURL = result.checkoutURL
      // Left running on purpose. The browser takes over from here, and the
      // purchase is only finished once we are back in the app and the balance
      // has been refreshed — `handlePaymentReturn` /
      // `handleCheckoutReturnWithoutResult` clear it, so the buyer comes back
      // to a spinner rather than an idle screen.
      logger.info("[PaymentReturn] checkout session created url=\(result.checkoutURL.absoluteString)")
    } catch let error as FunctionsError {
      isPreparingCheckout = false
      logger.error("[PaymentReturn] createCheckoutSession failed details=\(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.createCheckoutSession")
      searchState = .error(LocalizationSupport.localized("Could not start checkout."))
    } catch {
      isPreparingCheckout = false
      logger.error("[StudentHome] failed creating checkout session: \(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.createCheckoutSession")
      searchState = .error(LocalizationSupport.localized("Could not start checkout."))
    }
  }

  /// Apple Pay confirms entirely in-process via Braintree — no checkout URL/deep
  /// link round trip like the PayPal-redirect and hosted-card-page flows.
  #if canImport(UIKit)
  private func checkoutWithApplePay(_ option: PricingOption) async {
    do {
      let session = try await FunctionsService.shared.createApplePayCheckout(pricingOptionID: option.id)
      let nonce = try await ApplePayService.shared.startPayment(
        clientToken: session.clientToken,
        amountCents: session.amountCents,
        label: session.label
      )
      try await FunctionsService.shared.confirmApplePayPayment(checkoutId: session.checkoutId, nonce: nonce)
      logger.info("[PaymentReturn] Apple Pay confirmed checkoutId=\(session.checkoutId)")
      if let uid = Auth.auth().currentUser?.uid {
        _ = await refreshAfterPurchase(uid: uid, startingMinutes: checkoutStartedRemainingMinutes)
      }
      // Announced last so the summary appears with the new balance already in
      // place, rather than on top of the spinner that is still refreshing it.
      announcePurchase(option)
    } catch ApplePayService.ApplePayServiceError.cancelled {
      logger.info("[PaymentReturn] Apple Pay cancelled by user")
    } catch let error as FunctionsError {
      logger.error("[PaymentReturn] Apple Pay checkout failed details=\(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.applePayCheckout")
      searchState = .error(LocalizationSupport.localized("Could not start checkout."))
    } catch {
      logger.error("[PaymentReturn] Apple Pay checkout failed details=\(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.applePayCheckout")
      searchState = .error(LocalizationSupport.localized("Could not start checkout."))
    }
  }
  #else
  private func checkoutWithApplePay(_ option: PricingOption) async {
    logger.error("[PaymentReturn] Apple Pay checkout requested on a platform without UIKit")
    searchState = .error(LocalizationSupport.localized("Could not start checkout."))
  }
  #endif

  /// Charges the student's previously vaulted PayPal account directly — no
  /// checkout URL, no PayPal login, mirroring the wallet flows above.
  #if canImport(UIKit)
  private func checkoutWithSavedPayPal(_ option: PricingOption) async {
    do {
      try await FunctionsService.shared.chargeSavedPayPal(pricingOptionID: option.id)
      logger.info("[PaymentReturn] saved PayPal charged pricingOptionID=\(option.id)")
      if let uid = Auth.auth().currentUser?.uid {
        _ = await refreshAfterPurchase(uid: uid, startingMinutes: checkoutStartedRemainingMinutes)
      }
      announcePurchase(option)
    } catch let error as FunctionsError {
      logger.error("[PaymentReturn] saved PayPal charge failed details=\(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.chargeSavedPayPal")
      searchState = .error(LocalizationSupport.localized("Could not start checkout."))
    } catch {
      logger.error("[PaymentReturn] saved PayPal charge failed details=\(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.chargeSavedPayPal")
      searchState = .error(LocalizationSupport.localized("Could not start checkout."))
    }
  }
  #endif

  /// Google Pay is the Android mirror of Apple Pay — same Braintree
  /// create/confirm pair, no checkout URL or deep-link round trip.
  #if os(Android)
  private func checkoutWithGooglePay(_ option: PricingOption) async {
    do {
      let session = try await FunctionsService.shared.createGooglePayCheckout(pricingOptionID: option.id)
      let nonce = try await GooglePayService.shared.startPayment(
        clientToken: session.clientToken,
        amountCents: session.amountCents,
        currency: session.currency,
        merchantName: session.merchantName,
        countryCode: session.countryCode,
        environment: session.environment
      )
      try await FunctionsService.shared.confirmGooglePayPayment(checkoutId: session.checkoutId, nonce: nonce)
      logger.info("[PaymentReturn] Google Pay confirmed checkoutId=\(session.checkoutId)")
      if let uid = Auth.auth().currentUser?.uid {
        _ = await refreshAfterPurchase(uid: uid, startingMinutes: checkoutStartedRemainingMinutes)
      }
      announcePurchase(option)
    } catch GooglePayServiceError.cancelled {
      logger.info("[PaymentReturn] Google Pay cancelled by user")
    } catch let error as FunctionsError {
      logger.error("[PaymentReturn] Google Pay checkout failed details=\(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.googlePayCheckout")
      searchState = .error(LocalizationSupport.localized("Could not start checkout."))
    } catch {
      logger.error("[PaymentReturn] Google Pay checkout failed details=\(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.googlePayCheckout")
      searchState = .error(LocalizationSupport.localized("Could not start checkout."))
    }
  }
  #else
  private func checkoutWithGooglePay(_ option: PricingOption) async {
    logger.error("[PaymentReturn] Google Pay checkout requested on a non-Android platform")
    searchState = .error(LocalizationSupport.localized("Could not start checkout."))
  }
  #endif

  func consumeCheckoutURL() {
    checkoutURL = nil
  }

  func checkoutDidOpen() {
    isAwaitingPaymentReturn = true
    logger.info("[PaymentReturn] checkout opened; awaiting payment return")
    // The spinner is meant to sit under the browser and still be there on the
    // way back, but if the browser never actually opened there is nothing to
    // come back from — this stops that case from stranding a modal overlay the
    // buyer cannot dismiss. Coming back into the app re-arms it
    // (`resumeCheckoutSpinner`), so a long stay in the browser is unaffected.
    checkoutHandoffWatchdog?.cancel()
    checkoutHandoffWatchdog = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 90_000_000_000)
      guard !Task.isCancelled, let self, self.isAwaitingPaymentReturn else { return }
      self.isPreparingCheckout = false
    }
  }

  /// Puts the spinner back while a return from the browser is being resolved,
  /// so the buyer is not looking at an idle home screen between the payment
  /// finishing and the confirmation appearing.
  func resumeCheckoutSpinner() {
    guard isAwaitingPaymentReturn else { return }
    checkoutHandoffWatchdog?.cancel()
    isPreparingCheckout = true
  }

  func handlePaymentReturn(_ result: PaymentReturnResult) async {
    logger.info("[PaymentReturn] handling result status=\(String(describing: result.status)) rawURL=\(result.rawURL.absoluteString)")
    isAwaitingPaymentReturn = false
    checkoutHandoffWatchdog?.cancel()
    // The spinner has been up since the browser opened; it comes down here,
    // once the outcome is known and the balance is up to date, so the buyer
    // never sees an idle screen between returning and the confirmation.
    defer { isPreparingCheckout = false }
    if case .success = result.status {
      if let uid = Auth.auth().currentUser?.uid {
        _ = await refreshAfterPurchase(uid: uid, startingMinutes: checkoutStartedRemainingMinutes)
        logger.info("[PaymentReturn] success handled; refreshed lessons and remaining minutes")
      }
      announcePurchase(pendingPurchaseOption)
    }
  }

  func handleCheckoutReturnWithoutResult() async -> Bool {
    guard isAwaitingPaymentReturn else { return false }
    isAwaitingPaymentReturn = false
    checkoutHandoffWatchdog?.cancel()
    // Same hand-off as `handlePaymentReturn`: the spinner started when the
    // browser opened and only stops once we know where the purchase landed.
    defer { isPreparingCheckout = false }
    logger.info("[PaymentReturn] checkout returned without a deep link result")
    guard let uid = Auth.auth().currentUser?.uid else { return false }

    let startingMinutes = checkoutStartedRemainingMinutes
    let credited = await refreshAfterPurchase(
      uid: uid,
      startingMinutes: startingMinutes,
      retryDelays: Self.unconfirmedReturnPollDelays
    )
    // Only a confirmed balance increase proves the purchase went through; the
    // caller shows a "pending confirmation" notice otherwise.
    if credited {
      announcePurchase(pendingPurchaseOption)
    }
    return credited
  }

  /// Records what was bought so the view can confirm it to the buyer. Clears
  /// the pending option so a later return cannot re-announce a stale purchase.
  private func announcePurchase(_ option: PricingOption?) {
    guard let option else {
      logger.info("[PaymentReturn] purchase succeeded but the pricing option is unknown; no summary shown")
      return
    }
    purchaseSummary = PurchaseSummary(option: option)
    pendingPurchaseOption = nil
    logger.info("[PaymentReturn] purchase summary ready package=\(option.name) price=\(option.priceText)")
  }

  func consumePurchaseSummary() {
    purchaseSummary = nil
  }

  func redeemCoupon() async {
    let code = couponCode.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !code.isEmpty else { return }
    couponState = .loading
    do {
      let result = try await FunctionsService.shared.redeemCoupon(couponCode: code)
      couponCode = ""
      couponState = .success(minutesAdded: result.minutesAdded)
      if let uid = Auth.auth().currentUser?.uid {
        await loadRecentLessons(uid: uid)
      }
      logger.info("[Coupon] redeemed minutesAdded=\(result.minutesAdded)")
    } catch let err as FunctionsError {
      if case .serverError(let message, let status) = err {
        switch status {
        case "NOT_FOUND":
          couponState = .invalid
        case "FAILED_PRECONDITION":
          couponState = .alreadyActivated(date: message)
        default:
          couponState = .error(err.localizedDescription)
        }
      } else {
        couponState = .error(err.localizedDescription)
      }
      logger.error("[Coupon] redeem failed error=\(err.localizedDescription)")
    } catch {
      couponState = .error(error.localizedDescription)
      logger.error("[Coupon] redeem failed error=\(error.localizedDescription)")
    }
  }

  func resetCouponState() {
    couponState = .idle
  }

  func viewAllLessons() {}

  func loadProfileIfNeeded() async {
    await loadPricingOptions()
    await loadSubjectAvailability()
    startObservingOnlineTeachersIfNeeded()
    guard !didLoadProfile, let uid = Auth.auth().currentUser?.uid else {
      // Still worth showing the fee and connect time to a signed-out or
      // already-loaded screen; it just falls back to the default currency.
      return
    }
    didLoadProfile = true
    if let profile = try? await UserService.shared.fetchProfileSummary(uid: uid) {
      name = profile.displayName
      profileImageURL = profile.profileImageURL
      remainingMinutes = profile.remainingMinutes
      currencyCode = profile.currency
    }
    // After the profile, so the fee is quoted in the student's own currency.
    hasUnreadMessages = await UserService.shared.hasUnreadMessages(uid: uid)
    await loadRecentLessons(uid: uid)
  }

  /// Loads the published subject catalog — the same list teachers pick the
  /// subjects they teach from — and reads `enable_<key>` for each one. "math"
  /// defaults to visible; every other subject stays hidden until Remote Config
  /// turns it on.
  private func loadSubjectAvailability() async {
    await RemoteConfigService.shared.ready()
    subjectCatalog = (try? await SettingsRemoteConfigService.shared.fetchTeachingSubjects()) ?? []

    var enabled: Set<String> = []
    for subject in subjectCatalog {
      let key = SubjectPresentation.flagKey(for: subject.title)
      if RemoteConfigService.shared.getBool("enable_\(key)", default: key == "math") {
        enabled.insert(key)
      }
    }
    enabledSubjectKeys = enabled
    rebuildSubjects()
  }

  /// Joins the catalog with live presence. Called whenever either side
  /// changes, so the grid's teacher counts track teachers going on and offline.
  private func rebuildSubjects() {
    subjects = subjectCatalog.compactMap { subject in
      let key = SubjectPresentation.flagKey(for: subject.title)
      guard enabledSubjectKeys.contains(key) else { return nil }

      let englishTitle = SubjectPresentation.displayTitle(for: subject.title)
      return StudentSubject(
        key: key,
        title: LocalizationSupport.localized(englishTitle),
        topics: subject.subtopics
          .map { LocalizationSupport.localized($0) }
          .joined(separator: ", "),
        systemImage: SubjectPresentation.systemImage(for: subject.title),
        teacherCount: onlineTeacherCount(for: subject)
      )
    }
  }

  /// Teachers are online for a subject when any of the subtopic keys they
  /// published matches one of the subject's — the same normalized form the
  /// dispatcher matches on. The area name itself counts too, for a teacher who
  /// registered the area rather than its subtopics.
  private func onlineTeacherCount(for subject: RemoteTeachingSubject) -> Int {
    var keys = Set(subject.subtopics.map { SubjectPresentation.matchKey(for: $0) })
    keys.insert(SubjectPresentation.matchKey(for: subject.title))
    if subject.subtopics.isEmpty {
      // A subject published without subtopics is stored by teachers as "all".
      keys.insert("all")
    }
    keys.remove("")
    return onlineTeacherSubjectKeys.filter { !$0.isDisjoint(with: keys) }.count
  }


  // MARK: - Online Teachers

  private func startObservingOnlineTeachersIfNeeded() {
    guard onlineTeachersStore == nil else { return }
    let store = OnlineTeachersStore { [weak self] presences in
      self?.resolveOnlineTeachers(presences)
    }
    store.startListening()
    onlineTeachersStore = store
  }

  private func resolveOnlineTeachers(_ presences: [OnlineTeacherPresence]) {
    // The subject grid's teacher counts come straight from presence, so they
    // update the moment a teacher goes online.
    onlineTeacherSubjectKeys = presences.map { presence in
      Set(presence.subjects.map { SubjectPresentation.matchKey(for: $0) })
    }
    rebuildSubjects()

    // The projection already carries each teacher's name and photo, so the
    // grid is built straight from presence — no per-teacher profile reads, and
    // nothing to cache or invalidate.
    onlineTeachers = presences.map { presence in
      OnlineTeacher(
        id: presence.id,
        name: presence.displayName.isEmpty ? LocalizationSupport.localized("Teacher") : presence.displayName,
        subject: presence.subjects.first.map { LocalizationSupport.localized($0) } ?? LocalizationSupport.localized("Math"),
        profileImageURL: presence.photoUrl
      )
    }
  }

  /// Pull-to-refresh: re-reads the authoritative balance and profile summary
  /// from Firestore, along with recent lessons and unread messages.
  func refresh() async {
    await loadPricingOptions()
    await loadSubjectAvailability()
    guard let uid = Auth.auth().currentUser?.uid else { return }
    if let profile = try? await UserService.shared.fetchProfileSummary(uid: uid) {
      name = profile.displayName
      profileImageURL = profile.profileImageURL
      remainingMinutes = profile.remainingMinutes
      currencyCode = profile.currency
    }
    // Pull-to-refresh: re-read the measured connect time rather than reuse the
    // one cached when the screen first appeared.
    hasUnreadMessages = await UserService.shared.hasUnreadMessages(uid: uid)
    await loadRecentLessons(uid: uid)
  }

  func refreshAfterLessonEnded() async {
    guard let uid = Auth.auth().currentUser?.uid else { return }

    // `endLesson` debits the balance in a Firestore transaction that has often
    // not landed by the time the chat closes, so a single read here showed the
    // pre-lesson balance until the next pull-to-refresh. Wait for the debit the
    // same way refreshAfterPurchase waits for a credit.
    //
    // A lesson billed at zero minutes never changes the balance, so this always
    // stops after the last attempt rather than depending on seeing a change.
    let startingMinutes = remainingMinutes
    for attempt in 1...5 {
      await loadRemainingMinutes(uid: uid)
      await loadRecentLessons(uid: uid)
      if remainingMinutes < startingMinutes {
        logger.info("[StudentHome] balance debited after lesson attempt=\(attempt) minutes=\(self.remainingMinutes)")
        return
      }
      try? await Task.sleep(nanoseconds: 1_500_000_000)
    }
    logger.info("[StudentHome] balance unchanged after lesson startingMinutes=\(startingMinutes)")
  }

  /// Gaps between balance re-reads when we know money moved — a deep link said
  /// so, or a wallet returned a confirmed charge. PayPal's capture webhook is
  /// not instant, so this stays patient, but it looks several times in the
  /// first two seconds: when the credit has already landed, it has almost
  /// always landed by then, and the old flat 2s cadence made the buyer wait
  /// for a result we could have had immediately.
  private static let confirmedPurchasePollDelays: [Double] = [0.3, 0.5, 0.9, 1.5, 2.5, 4, 4, 4]

  /// Gaps to use when the buyer came back from the browser with nothing to say
  /// a payment was ever made. PayPal captures during its own return redirect,
  /// so a completed payment nearly always arrives with a deep link — no deep
  /// link means a cancel in all but the rarest case. This gives a late credit
  /// a couple of seconds to appear and then stops, instead of holding the
  /// spinner for the full patient schedule before saying "cancelled".
  private static let unconfirmedReturnPollDelays: [Double] = [0.4, 0.6, 1.0]

  private func refreshAfterPurchase(
    uid: String,
    startingMinutes: Int,
    retryDelays: [Double] = StudentHomeViewModel.confirmedPurchasePollDelays
  ) async -> Bool {
    var attempt = 0
    while true {
      await loadRemainingMinutes(uid: uid)
      await loadRecentLessons(uid: uid)
      logger.info("[PaymentReturn] balance refresh attempt=\(attempt + 1) startingMinutes=\(startingMinutes) currentMinutes=\(self.remainingMinutes)")
      if remainingMinutes > startingMinutes {
        logger.info("[PaymentReturn] balance increased after checkout")
        return true
      }
      guard attempt < retryDelays.count else { return false }
      try? await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
      attempt += 1
    }
  }

  /// Reads the authoritative remaining-minutes balance straight from the
  /// `users/{uid}` Firestore document rather than deriving it on the client.
  private func loadRemainingMinutes(uid: String) async {
    if let profile = try? await UserService.shared.fetchProfileSummary(uid: uid) {
      remainingMinutes = profile.remainingMinutes
    }
  }

  func refreshUnreadMessages() async {
    guard let uid = Auth.auth().currentUser?.uid else { return }
    hasUnreadMessages = await UserService.shared.hasUnreadMessages(uid: uid)
  }

  private func loadPricingOptions() async {
    await loadPaymentMethods()
    do {
      pricingOptions = try await PricingService.shared.fetchPricingOptions()
    } catch {
      logger.error("[StudentHome] failed loading pricing options: \(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.loadPricingOptions")
    }
  }

  /// Resolves which payment methods to offer from Remote Config, falling back to
  /// the built-in per-platform defaults. Awaits the first Remote Config fetch so
  /// the configured list (if any) is applied rather than a stale/empty value.
  private func loadPaymentMethods() async {
    await RemoteConfigService.shared.ready()
    var methods = PaymentMethod.configuredForCheckout()
#if canImport(UIKit)
    if !ApplePayService.shared.canMakePayments() {
      methods = methods.filter { $0 != .applePay }
    }
    if let uid = Auth.auth().currentUser?.uid {
      savedPayPalEmail = try? await UserService.shared.fetchSavedPayPalEmail(uid: uid)
    }
    // A saved account replaces the redirect-based PayPal entry outright —
    // charging it goes through chargeSavedPayPal directly, so both options
    // would just be two ways to pay with the same PayPal account.
    if savedPayPalEmail != nil {
      methods = methods.map { $0 == .paypal ? .savedPayPal : $0 }
    }
#endif
    availablePaymentMethods = methods
  }

  private func loadRecentLessons(uid: String) async {
    do {
      let currencyCode = try await HistoryModel.shared.fetchPurchasedCurrencyCode(for: uid)
      purchasedCurrencyCode = currencyCode
      let allLessons = try await HistoryModel.shared.fetchRecentLessons(for: uid, limit: 100)
      let totalPurchasedMinutes = try await HistoryModel.shared.fetchTotalPurchasedMinutes(for: uid)
      lessonCount = allLessons.count
      totalTimeLearnedText = LessonFormatting.totalDurationText(lessons: allLessons)
      totalPurchasedText = LessonFormatting.minutesText(totalPurchasedMinutes)
      let recent = Array(allLessons.prefix(3))
      if !recent.isEmpty {
        recentLessons = recent.map(Self.recentLesson)
      }
    } catch {
      logger.error("[StudentHome] failed loading recent lessons: \(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.loadRecentLessons")
    }
  }

  func chatInitialDetails(questionId: String? = nil) -> ChatSessionDetails {
    ChatSessionDetails(
	  questionId: questionId ?? "",
      studentId: Auth.auth().currentUser?.uid ?? "",
      teacherId: "",
      studentName: name,
      teacherName: "Teacher",
      studentImageURL: profileImageURL,
      teacherImageURL: "",
      questionText: activeQuestionText,
      questionPhotoUrls: [],
      createdAt: 0,
      acceptedAt: Date().timeIntervalSince1970 * 1000.0,
      pricePerMinuteCents: selectedPricePerMinuteCents,
      teacherSharePercent: 75,
      currencyCode: purchasedCurrencyCode
    )
  }

  // MARK: - Polling

  private static let noTeacherTimeoutSeconds: Double = 60

  private func startPolling(questionId: String) {
    pollingTask?.cancel()
    let startedAt = Date().timeIntervalSince1970
    pollingTask = Task {
      while !Task.isCancelled {
        do {
          let result = try await currentQuestionStatus(questionId: questionId)
          let status = result.status.lowercased()
          logger.info("TeacherMinute questionStatus questionId=\(questionId) status=\(result.status)")

          if isAcceptedStatus(status) {
            let room = result.liveKitRoom ?? ""
            let token = result.liveKitToken ?? ""
            if self.requiresMediaConnection(conversationType: self.activeConversationType), (room.isEmpty || token.isEmpty) {
              logger.info("TeacherMinute questionStatus accepted but media credentials missing questionId=\(questionId) roomEmpty=\(room.isEmpty) tokenEmpty=\(token.isEmpty) conversationType=\(self.activeConversationType)")
              try? await Task.sleep(nanoseconds: 1_000_000_000)
              continue
            }
            self.questionId = result.questionId
            searchState = .matched(
              questionId: questionId,
              liveKitRoom: room,
              liveKitToken: token
            )
            return
          }

          switch status {
          case "unanswered", "waiting", "pending":
            break
          case "cancelled", "canceled", "expired":
            searchState = .noMatch
            return
          case "completed":
            // Completed without an AI answer means the question was force-ended
            // or cancelled server-side before a teacher connected.
            searchState = .noMatch
            return
          default:
            break
          }

          let elapsed = Date().timeIntervalSince1970 - startedAt
          if elapsed >= Self.noTeacherTimeoutSeconds {
            logger.info("TeacherMinute questionStatus timed out after \(Int(elapsed))s questionId=\(questionId); transitioning to noMatch")
            try? await FunctionsService.shared.cancelQuestion(questionId: questionId)
            searchState = .noMatch
            return
          }
        } catch {
          guard !Task.isCancelled else { return }
          logger.error("TeacherMinute questionStatus polling error=\(error)")
        }

        try? await Task.sleep(nanoseconds: 1_000_000_000)
      }
    }
  }

  private func currentQuestionStatus(questionId: String) async throws -> QuestionStatusResult {
    let functionResult = try await FunctionsService.shared.getQuestionStatus(questionId: questionId)
    let functionStatus = functionResult.status.lowercased()
    guard !isAcceptedStatus(functionStatus), functionStatus != "cancelled", functionStatus != "canceled" else {
      return functionResult
    }

    if let realtimeResult = try? await QuestionStatusStore.fetch(questionId: questionId) {
      let realtimeStatus = realtimeResult.status.lowercased()
      if isAcceptedStatus(realtimeStatus) || realtimeStatus == "cancelled" || realtimeStatus == "canceled" {
        logger.info("TeacherMinute questionStatus realtimeOverride questionId=\(questionId) status=\(realtimeResult.status)")
        return realtimeResult
      }
    }

    return functionResult
  }

  private func requiresMediaConnection(conversationType: String) -> Bool {
    conversationType == "audio" || conversationType == "video"
  }

  private func isAcceptedStatus(_ status: String) -> Bool {
    status == "accepted"
      || status == "in_progress"
      || status == "matched"
      || status == "connected"
      || status == "active"
  }

  private static func recentLesson(_ lesson: HistoryLesson) -> RecentLesson {
    RecentLesson(
      title: lesson.title,
      teacher: String(format: LocalizationSupport.localized("with %@"), lesson.otherParticipantName),
      teacherImageURL: lesson.otherParticipantImageURL,
      time: LessonFormatting.relativeDateText(lesson.acceptedAt),
      duration: LessonFormatting.durationText(seconds: lesson.durationSeconds),
      rating: lesson.studentRating
    )
  }
}

@Observable
@MainActor
final class MockStudentHomeViewModel: StudentHomeViewModeling {
  var name: String
  var searchState: StudentSearchState
  var activeQuestionText: String
  var activeConversationType: String = "text"
  var selectedPricePerMinuteCents: Int
  var questionId: String?

  let pricingOptions: [PricingOption]
  var availablePaymentMethods: [PaymentMethod] = PaymentMethod.availableForCurrentPlatform
  var savedPayPalEmail: String?
  var recentLessons: [RecentLesson]
  var onlineTeachers: [OnlineTeacher] = [
    OnlineTeacher(id: "1", name: "Cohen", subject: "Math", profileImageURL: ""),
    OnlineTeacher(id: "2", name: "Levi", subject: "Physics", profileImageURL: ""),
    OnlineTeacher(id: "3", name: "Mizrahi", subject: "Chemistry", profileImageURL: ""),
    OnlineTeacher(id: "4", name: "Shalev", subject: "Statistics", profileImageURL: ""),
  ]
  var totalTimeLearnedText: String
  var totalPurchasedText: String
  var lessonCount: Int
  var hasUnreadMessages: Bool
  var profileImageURL: String
  var remainingMinutes: Int
  var checkoutURL: URL?
  var isStartingCheckout = false
  /// True from the moment checkout starts until the buyer is handed off to
  /// something they can see — the wallet sheet, or the browser. Distinct from
  /// `isStartingCheckout`, which stays true for the whole wallet payment and
  /// so would leave a spinner sitting behind the Apple Pay sheet.
  var isPreparingCheckout = false
  var checkoutPricingOptionID: String?
  var isAwaitingPaymentReturn = false
  var couponCode = ""
  var couponState: CouponRedemptionState = .idle
  var purchaseSummary: PurchaseSummary?

  init(
    name: String = "Sarah Jenkins",
    searchState: StudentSearchState = .idle,
    activeQuestionText: String = "",
    selectedPricePerMinuteCents: Int = 50,
    remainingMinutes: Int = 30,
    pricingOptions: [PricingOption] = [
      PricingOption(
        id: "standard_pay_as_you_go",
        name: "Standard",
        priceCents: 50,
        currency: "USD",
        type: .payAsYouGo,
        description: "Verified tutors for algebra, geometry, and basic calculus.",
        isHighlighted: false,
        sortOrder: 0,
        purchaseSKU: nil,
        minutesGranted: 30
      ),
      PricingOption(
        id: "expert_pay_as_you_go",
        name: "Expert",
        priceCents: 120,
        currency: "USD",
        type: .payAsYouGo,
        description: "Advanced degree tutors for college-level help.",
        isHighlighted: true,
        sortOrder: 1,
        purchaseSKU: nil,
        minutesGranted: 60
      ),
    ],
    recentLessons: [RecentLesson] = [
      RecentLesson(title: "Calculus Help", teacher: "with Mr. Davis", teacherImageURL: "", time: "Today, 2:30 PM", duration: "14 mins", rating: 5),
      RecentLesson(title: "Algebra II", teacher: "with Ms. Chen", teacherImageURL: "", time: "Yesterday", duration: "22 mins", rating: 4),
    ]
  ) {
    self.name = name
    self.searchState = searchState
    self.activeQuestionText = activeQuestionText
    self.selectedPricePerMinuteCents = selectedPricePerMinuteCents
    self.remainingMinutes = remainingMinutes
    self.questionId = "mock-lesson"
    self.pricingOptions = pricingOptions
    self.recentLessons = recentLessons
    self.totalTimeLearnedText = LessonFormatting.minutesText(36)
    self.totalPurchasedText = LessonFormatting.minutesText(90)
    self.lessonCount = recentLessons.count
    self.hasUnreadMessages = true
    self.profileImageURL = ""
  }

  func askTeacher(topic: String, text: String, photoUrls: [String], conversationType: String) async {
    activeQuestionText = text
    activeConversationType = conversationType
    searchState = .searching(questionId: "mock-question")
  }

  func cancelSearch() async {
    searchState = .idle
  }

  func resetSearch() {
    searchState = .idle
  }

  func selectTier(_ option: PricingOption) {
    selectedPricePerMinuteCents = option.priceCents
  }

  func preparePaymentOptions() async {
    isPreparingCheckout = true
  }

  func checkout(_ option: PricingOption, method: PaymentMethod = .paypal) async {
    selectTier(option)
  }

  func consumeCheckoutURL() {
    checkoutURL = nil
  }

  func checkoutDidOpen() {
    isAwaitingPaymentReturn = true
    logger.info("[PaymentReturn] mock checkout opened")
  }

  func resumeCheckoutSpinner() {
    guard isAwaitingPaymentReturn else { return }
    isPreparingCheckout = true
  }

  func handlePaymentReturn(_ result: PaymentReturnResult) async {
    logger.info("[PaymentReturn] mock handling result status=\(String(describing: result.status))")
    isAwaitingPaymentReturn = false
  }

  func handleCheckoutReturnWithoutResult() async -> Bool {
    isAwaitingPaymentReturn = false
    logger.info("[PaymentReturn] mock checkout returned without result")
    return false
  }

  func redeemCoupon() async {
    couponState = .success(minutesAdded: 30)
  }

  func resetCouponState() {
    couponState = .idle
  }

  func consumePurchaseSummary() {
    purchaseSummary = nil
  }

  func viewAllLessons() {}

  var subjects: [StudentSubject] = [
    StudentSubject(key: "math", title: "Math", topics: "Algebra, Trigonometry", systemImage: "function", teacherCount: 3),
    StudentSubject(key: "physics", title: "Physics", topics: "Mechanics", systemImage: "atom", teacherCount: 1),
  ]
  var pricePerMinuteText = "2 NIS per minute • pay only for time used"
  var averageConnectText = "90 sec avg to connect"
  var registeredTeacherCountText = "237 registered teachers"
  var connectPromiseText = "Help from a real teacher, exactly when you need it Mock"
  var appMainIssueText = "Stuck? You will have a teacher immediately"
  var connectStepTitle = "Teacher connects within 90 sec"
  var averageResponseText = "Average response time: 90 seconds"

  func loadProfileIfNeeded() async {}

  func refresh() async {}

  func refreshAfterLessonEnded() async {}

  func refreshUnreadMessages() async {
    hasUnreadMessages = false
  }

  func chatInitialDetails(questionId: String? = nil) -> ChatSessionDetails {
    ChatSessionDetails(
      questionId: questionId ?? "mock-lesson",
      studentId: "mock-student",
      teacherId: "mock-teacher",
      studentName: name,
      teacherName: "Teacher",
      studentImageURL: profileImageURL,
      teacherImageURL: "",
      questionText: activeQuestionText,
      questionPhotoUrls: [],
      createdAt: 0,
      acceptedAt: Date().timeIntervalSince1970 * 1000.0,
      pricePerMinuteCents: selectedPricePerMinuteCents,
      teacherSharePercent: 75,
      currencyCode: pricingOptions.first?.currency ?? LessonFormatting.defaultCurrencyCode
    )
  }
}
