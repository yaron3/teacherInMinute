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
    return String(format: LocalizationSupport.localized("%lld min"), Int64(minutes))
  }
}

struct RecentLesson: Identifiable {
  let id = UUID()
  let title: String
  let teacher: String
  let teacherImageURL: String
  let time: String
  let duration: String
}

// MARK: - ViewModel Protocol

@MainActor
protocol StudentHomeViewModeling: AnyObject {
  var name: String { get set }
  var searchState: StudentSearchState { get set }
  var activeQuestionText: String { get set }
  var activeConnectionFeeCents: Int { get set }
  var selectedPricePerMinuteCents: Int { get set }
  var questionId: String? { get set }
  var pricingOptions: [PricingOption] { get }
  var recentLessons: [RecentLesson] { get set }
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

  func askTeacher(topic: String, text: String, photoUrls: [String], conversationType: String) async
  func cancelSearch() async
  func resetSearch()
  func selectTier(_ option: PricingOption)
  func checkout(_ option: PricingOption) async
  func consumeCheckoutURL()
  func checkoutDidOpen()
  func handlePaymentReturn(_ result: PaymentReturnResult) async
  func handleCheckoutReturnWithoutResult() async -> Bool
  func viewAllLessons()
  func loadProfileIfNeeded() async
  func refreshAfterLessonEnded() async
  func refreshUnreadMessages() async
  func chatInitialDetails(questionId: String?) -> ChatSessionDetails
}

// MARK: - ViewModel

@Observable
@MainActor
final class StudentHomeViewModel: StudentHomeViewModeling {

  var name = ""
  var searchState: StudentSearchState = .idle
  var activeQuestionText = ""
  var activeConnectionFeeCents = 0
  var selectedPricePerMinuteCents = 50
  var questionId: String?

  var pricingOptions: [PricingOption] = []

  var recentLessons: [RecentLesson] = []
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

  private var pollingTask: Task<Void, Never>?
  private var didLoadProfile = false
  private var checkoutStartedRemainingMinutes = 0
  private var purchasedCurrencyCode = LessonFormatting.defaultCurrencyCode

  // MARK: - Actions

  func askTeacher(topic: String, text: String, photoUrls: [String] = [], conversationType: String = "text") async {
    guard case .idle = searchState else { return }
	logger.info("TeacherMinute askTeacher submit topic=\(topic) textLength=\(text.count)")
    searchState = .searching(questionId: "")
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

  func checkout(_ option: PricingOption) async {
    guard !isStartingCheckout else { return }
    logger.info("[PaymentReturn] checkout start pricingOptionID=\(option.id)")
    isStartingCheckout = true
    checkoutPricingOptionID = option.id
    checkoutStartedRemainingMinutes = remainingMinutes
    defer {
      isStartingCheckout = false
      checkoutPricingOptionID = nil
    }
    selectTier(option)

    do {
      let result = try await FunctionsService.shared.createCheckoutSession(pricingOptionID: option.id)
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
    if case .success = result.status, let uid = Auth.auth().currentUser?.uid {
      _ = await refreshAfterPurchase(uid: uid, startingMinutes: checkoutStartedRemainingMinutes)
      logger.info("[PaymentReturn] success handled; refreshed lessons and remaining minutes")
    }
  }

  func handleCheckoutReturnWithoutResult() async -> Bool {
    guard isAwaitingPaymentReturn else { return false }
    isAwaitingPaymentReturn = false
    logger.info("[PaymentReturn] checkout returned without a deep link result")
    guard let uid = Auth.auth().currentUser?.uid else { return false }

    let startingMinutes = checkoutStartedRemainingMinutes
    return await refreshAfterPurchase(uid: uid, startingMinutes: startingMinutes)
  }

  func viewAllLessons() {}

  func loadProfileIfNeeded() async {
    await loadPricingOptions()
    guard !didLoadProfile, let uid = Auth.auth().currentUser?.uid else { return }
    didLoadProfile = true
    if let profile = try? await UserService.shared.fetchProfileSummary(uid: uid) {
      name = profile.displayName
      profileImageURL = profile.profileImageURL
    }
    hasUnreadMessages = await UserService.shared.hasUnreadMessages(uid: uid)
    await loadRecentLessons(uid: uid)
  }

  func refreshAfterLessonEnded() async {
    guard let uid = Auth.auth().currentUser?.uid else { return }
    await loadRecentLessons(uid: uid)
  }

  private func refreshAfterPurchase(uid: String, startingMinutes: Int) async -> Bool {
    for attempt in 1...8 {
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

  func refreshUnreadMessages() async {
    guard let uid = Auth.auth().currentUser?.uid else { return }
    hasUnreadMessages = await UserService.shared.hasUnreadMessages(uid: uid)
  }

  private func loadPricingOptions() async {
    do {
      pricingOptions = try await PricingService.shared.fetchPricingOptions()
    } catch {
      logger.error("[StudentHome] failed loading pricing options: \(error.localizedDescription)")
      AnalyticsService.shared.recordPermissionIfNeeded(error, context: "StudentHome.loadPricingOptions")
    }
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
      remainingMinutes = max(0, totalPurchasedMinutes - Self.totalUsedMinutes(lessons: allLessons))
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
      createdAt: 0,
      acceptedAt: Date().timeIntervalSince1970 * 1000.0,
      connectionFeeCents: activeConnectionFeeCents,
      pricePerMinuteCents: selectedPricePerMinuteCents,
      teacherSharePercent: 75,
      currencyCode: purchasedCurrencyCode
    )
  }

  // MARK: - Polling

  private func startPolling(questionId: String) {
    pollingTask?.cancel()
    pollingTask = Task {
      while !Task.isCancelled {
        do {
          let result = try await currentQuestionStatus(questionId: questionId)
          let status = result.status.lowercased()
		  logger.info("TeacherMinute questionStatus questionId=\(questionId) status=\(result.status)")

          if isAcceptedStatus(status) {
			self.questionId = result.questionId
            searchState = .matched(
              questionId: questionId,
              liveKitRoom: result.liveKitRoom ?? "",
              liveKitToken: result.liveKitToken ?? ""
            )
            return
          }

          switch status {
          case "unanswered", "waiting", "pending":
            break
          case "cancelled", "canceled", "expired":
            searchState = .noMatch
            return
          default:
            break
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

  private func isAcceptedStatus(_ status: String) -> Bool {
    status == "accepted"
      || status == "in_progress"
      || status == "matched"
      || status == "connected"
      || status == "active"
  }

  private static func totalUsedMinutes(lessons: [HistoryLesson]) -> Int {
    let totalSeconds = lessons.reduce(0) { $0 + $1.durationSeconds }
    guard totalSeconds > 0 else { return 0 }
    return Int(ceil(Double(totalSeconds) / 60.0))
  }

  private static func recentLesson(_ lesson: HistoryLesson) -> RecentLesson {
    RecentLesson(
      title: lesson.title,
      teacher: "with \(lesson.otherParticipantName)",
      teacherImageURL: lesson.otherParticipantImageURL,
      time: LessonFormatting.relativeDateText(lesson.acceptedAt),
      duration: LessonFormatting.durationText(seconds: lesson.durationSeconds)
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
  var selectedPricePerMinuteCents: Int
  var questionId: String?

  let pricingOptions: [PricingOption]
  var recentLessons: [RecentLesson]
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
      RecentLesson(title: "Calculus Help", teacher: "with Mr. Davis", teacherImageURL: "", time: "Today, 2:30 PM", duration: "14 mins"),
      RecentLesson(title: "Algebra II", teacher: "with Ms. Chen", teacherImageURL: "", time: "Yesterday", duration: "22 mins"),
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

  func checkout(_ option: PricingOption) async {
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

  func viewAllLessons() {}

  func loadProfileIfNeeded() async {}

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
      createdAt: 0,
      acceptedAt: Date().timeIntervalSince1970 * 1000.0,
      connectionFeeCents: activeConnectionFeeCents,
      pricePerMinuteCents: selectedPricePerMinuteCents,
      teacherSharePercent: 75,
      currencyCode: pricingOptions.first?.currency ?? LessonFormatting.defaultCurrencyCode
    )
  }
}
