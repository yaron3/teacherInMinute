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
  var activeConnectionFeeCents: Int { get set }
  var activeConversationType: String { get set }
  var selectedPricePerMinuteCents: Int { get set }
  var questionId: String? { get set }
  var pricingOptions: [PricingOption] { get }
  var availablePaymentMethods: [PaymentMethod] { get }
  var savedPayPalEmail: String? { get set }
  var recentLessons: [RecentLesson] { get set }
  var onlineTeachers: [OnlineTeacher] { get set }
  var subjects: [StudentSubject] { get }
  var connectionFeeText: String { get }
  var averageConnectText: String { get }
  var connectPromiseText: String { get }
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
  var checkoutPricingOptionID: String? { get set }
  var isAwaitingPaymentReturn: Bool { get set }
  var couponCode: String { get set }
  var couponState: CouponRedemptionState { get set }
  var purchaseSummary: PurchaseSummary? { get set }

  func askTeacher(topic: String, text: String, photoUrls: [String], conversationType: String) async
  func cancelSearch() async
  func resetSearch()
  func selectTier(_ option: PricingOption)
  func checkout(_ option: PricingOption, method: PaymentMethod) async
  func consumeCheckoutURL()
  func checkoutDidOpen()
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

// MARK: - ViewModel

@Observable
@MainActor
final class StudentHomeViewModel: StudentHomeViewModeling {

  var name = ""
  var searchState: StudentSearchState = .idle
  var activeQuestionText = ""
  var activeConnectionFeeCents = 0
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
  /// "2₪ connection fee • pay only for time used" — the fee is the one the
  /// backend bills, not a number written into the copy.
  var connectionFeeText = ""
  /// "90 sec avg to connect", measured by the backend. Empty until there is a
  /// measurement, so the view can leave the claim out entirely.
  var averageConnectText = ""
  /// "237 registered teachers", counted by the backend. Empty until the counter
  /// is seeded, so the view omits the caption rather than claiming zero.
  var registeredTeacherCountText = ""
  /// The hero line and the "how it works" step, both of which used to promise a
  /// fixed 90 seconds. They now quote the measured average, and fall back to
  /// wording that makes no numeric claim when there is nothing to quote.
  var connectPromiseText = LocalizationSupport.localized("When AI gets stuck, a human teacher connects in moments")
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
  /// The student's own currency, so the connection fee is quoted in it.
  private var currencyCode = LessonFormatting.defaultCurrencyCode
  private var didLoadProfile = false
  private var checkoutStartedRemainingMinutes = 0
  /// The option being bought. Unlike `checkoutPricingOptionID` this survives
  /// the end of `checkout(_:method:)`, because the redirect flows only learn
  /// the purchase succeeded once the buyer comes back from the browser.
  private var pendingPurchaseOption: PricingOption?
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
      activeConnectionFeeCents = result.connectionFeeCents
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

  func checkout(_ option: PricingOption, method: PaymentMethod = .paypal) async {
    guard !isStartingCheckout else { return }
    logger.info("[PaymentReturn] checkout start pricingOptionID=\(option.id) method=\(method.rawValue)")
    isStartingCheckout = true
    checkoutPricingOptionID = option.id
    checkoutStartedRemainingMinutes = remainingMinutes
    pendingPurchaseOption = option
    defer {
      isStartingCheckout = false
      checkoutPricingOptionID = nil
    }
    selectTier(option)

    if method == .applePay {
      await checkoutWithApplePay(option)
      return
    }

    if method == .googlePay {
      await checkoutWithGooglePay(option)
      return
    }

#if canImport(UIKit)
    if method == .savedPayPal {
      await checkoutWithSavedPayPal(option)
      return
    }
#endif

    do {
      let result = try await FunctionsService.shared.createCheckoutSession(pricingOptionID: option.id, paymentMethod: method)
      checkoutURL = result.checkoutURL
      logger.info("[PaymentReturn] checkout session created url=\(result.checkoutURL.absoluteString)")
    } catch let error as FunctionsError {
      logger.error("[PaymentReturn] createCheckoutSession failed details=\(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.createCheckoutSession")
      searchState = .error(LocalizationSupport.localized("Could not start checkout."))
    } catch {
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
      announcePurchase(option)

      if let uid = Auth.auth().currentUser?.uid {
        _ = await refreshAfterPurchase(uid: uid, startingMinutes: checkoutStartedRemainingMinutes)
      }
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
      announcePurchase(option)

      if let uid = Auth.auth().currentUser?.uid {
        _ = await refreshAfterPurchase(uid: uid, startingMinutes: checkoutStartedRemainingMinutes)
      }
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
      announcePurchase(option)

      if let uid = Auth.auth().currentUser?.uid {
        _ = await refreshAfterPurchase(uid: uid, startingMinutes: checkoutStartedRemainingMinutes)
      }
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
  }

  func handlePaymentReturn(_ result: PaymentReturnResult) async {
    logger.info("[PaymentReturn] handling result status=\(String(describing: result.status)) rawURL=\(result.rawURL.absoluteString)")
    isAwaitingPaymentReturn = false
    if case .success = result.status {
      announcePurchase(pendingPurchaseOption)
      if let uid = Auth.auth().currentUser?.uid {
        _ = await refreshAfterPurchase(uid: uid, startingMinutes: checkoutStartedRemainingMinutes)
        logger.info("[PaymentReturn] success handled; refreshed lessons and remaining minutes")
      }
    }
  }

  func handleCheckoutReturnWithoutResult() async -> Bool {
    guard isAwaitingPaymentReturn else { return false }
    isAwaitingPaymentReturn = false
    logger.info("[PaymentReturn] checkout returned without a deep link result")
    guard let uid = Auth.auth().currentUser?.uid else { return false }

    let startingMinutes = checkoutStartedRemainingMinutes
    let credited = await refreshAfterPurchase(uid: uid, startingMinutes: startingMinutes)
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
      await loadPlatformFigures()
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
    await loadPlatformFigures()
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

  /// The connection fee and the measured time-to-connect, both from the
  /// backend. Either can be missing, in which case the view shows nothing
  /// rather than a figure the app invented.
  private func loadPlatformFigures(forceRefresh: Bool = false) async {
    let feeCents = await SettingsRemoteConfigService.shared.fetchConnectionFeeCents()
    connectionFeeText = String(
      format: LocalizationSupport.localized("%@ connection fee • pay only for time used"),
      LessonFormatting.currencyText(cents: feeCents, currencyCode: currencyCode)
    )

    let stats = await PlatformStatsService.shared.fetchStats(forceRefresh: forceRefresh)

    // Set before the connect-time guard below: the two counters are
    // independent, and a platform with no connect samples yet can still have
    // registered teachers.
    registeredTeacherCountText = stats.hasRegisteredTeachers
      ? String(format: LocalizationSupport.localized("%d registered teachers"), stats.registeredTeacherCount)
      : ""

    guard stats.hasConnectTime else {
      averageConnectText = ""
      averageResponseText = ""
      connectPromiseText = LocalizationSupport.localized("When AI gets stuck, a human teacher connects in moments")
      connectStepTitle = LocalizationSupport.localized("A teacher connects quickly")
      return
    }

    averageResponseText = String(
      format: LocalizationSupport.localized("Average response time: %@"),
      LessonFormatting.connectDurationText(seconds: stats.averageConnectSeconds)
    )

    averageConnectText = LessonFormatting.averageConnectText(seconds: stats.averageConnectSeconds)
    connectPromiseText = String(
      format: LocalizationSupport.localized("When AI gets stuck, a human teacher connects in %@"),
      LessonFormatting.connectDurationText(seconds: stats.averageConnectSeconds)
    )
    connectStepTitle = String(
      format: LocalizationSupport.localized("Teacher connects within %@"),
      LessonFormatting.connectDurationShortText(seconds: stats.averageConnectSeconds)
    )
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
    await loadPlatformFigures(forceRefresh: true)
    hasUnreadMessages = await UserService.shared.hasUnreadMessages(uid: uid)
    await loadRecentLessons(uid: uid)
  }

  func refreshAfterLessonEnded() async {
    guard let uid = Auth.auth().currentUser?.uid else { return }
    await loadRemainingMinutes(uid: uid)
    await loadRecentLessons(uid: uid)
  }

  private func refreshAfterPurchase(uid: String, startingMinutes: Int) async -> Bool {
    for attempt in 1...8 {
      await loadRemainingMinutes(uid: uid)
      await loadRecentLessons(uid: uid)
      logger.info("[PaymentReturn] balance refresh attempt=\(attempt) startingMinutes=\(startingMinutes) currentMinutes=\(self.remainingMinutes)")
      if remainingMinutes > startingMinutes {
        logger.info("[PaymentReturn] balance increased after checkout")
        return true
      }
      try? await Task.sleep(nanoseconds: 2_000_000_000)
    }
    return false
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
      connectionFeeCents: activeConnectionFeeCents,
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
  var activeConnectionFeeCents: Int
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
  var checkoutPricingOptionID: String?
  var isAwaitingPaymentReturn = false
  var couponCode = ""
  var couponState: CouponRedemptionState = .idle
  var purchaseSummary: PurchaseSummary?

  init(
    name: String = "Sarah Jenkins",
    searchState: StudentSearchState = .idle,
    activeQuestionText: String = "",
    activeConnectionFeeCents: Int = 0,
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
    self.activeConnectionFeeCents = activeConnectionFeeCents
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
    activeConnectionFeeCents = 50
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
  var connectionFeeText = "2₪ connection fee • pay only for time used"
  var averageConnectText = "90 sec avg to connect"
  var registeredTeacherCountText = "237 registered teachers"
  var connectPromiseText = "When AI gets stuck, a human teacher connects in 90 seconds"
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
      connectionFeeCents: activeConnectionFeeCents,
      pricePerMinuteCents: selectedPricePerMinuteCents,
      teacherSharePercent: 75,
      currencyCode: pricingOptions.first?.currency ?? LessonFormatting.defaultCurrencyCode
    )
  }
}
