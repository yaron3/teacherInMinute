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

  var priceText: String {
    let amount = Double(priceCents) / 100.0
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = currency
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
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
  var totalSpendText: String { get }
  var lessonCount: Int { get }
  var hasUnreadMessages: Bool { get set }
  var profileImageURL: String { get set }

  func askTeacher(topic: String, text: String, photoUrls: [String], conversationType: String) async
  func cancelSearch() async
  func resetSearch()
  func selectTier(_ option: PricingOption)
  func viewAllLessons()
  func loadProfileIfNeeded() async
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
  var totalTimeLearnedText = "0 min"
  var totalSpendText = "$0.00"
  var lessonCount = 0
  var hasUnreadMessages = false
  var profileImageURL = ""

  private var pollingTask: Task<Void, Never>?
  private var didLoadProfile = false

  // MARK: - Actions

  func askTeacher(topic: String, text: String, photoUrls: [String] = [], conversationType: String = "text") async {
    guard case .idle = searchState else { return }
    print("TeacherMinute askTeacher submit topic=\(topic) textLength=\(text.count)")
    searchState = .searching(questionId: "")
    do {
      let result = try await FunctionsService.shared.createQuestion(
        topic: topic,
        text: text,
        photoUrls: photoUrls,
        conversationType: conversationType
      )
      print("TeacherMinute askTeacher created questionId=\(result.questionId)")
      activeQuestionText = text
      activeConnectionFeeCents = result.connectionFeeCents
      searchState = .searching(questionId: result.questionId)
      startPolling(questionId: result.questionId)
    } catch {
      print("TeacherMinute askTeacher failed error=\(error)")
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

  private func loadPricingOptions() async {
    do {
      pricingOptions = try await PricingService.shared.fetchPricingOptions()
    } catch {
      logger.error("[StudentHome] failed loading pricing options: \(error.localizedDescription)")
    }
  }

  private func loadRecentLessons(uid: String) async {
    do {
      let allLessons = try await HistoryModel.shared.fetchRecentLessons(for: uid, limit: 100)
      lessonCount = allLessons.count
      totalTimeLearnedText = LessonFormatting.totalDurationText(lessons: allLessons)
      totalSpendText = LessonFormatting.totalCostText(lessons: allLessons)
      let recent = Array(allLessons.prefix(3))
      if !recent.isEmpty {
        recentLessons = recent.map(Self.recentLesson)
      }
    } catch {
      logger.error("[StudentHome] failed loading recent lessons: \(error.localizedDescription)")
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
      teacherSharePercent: 75
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
          print("TeacherMinute questionStatus questionId=\(questionId) status=\(result.status)")

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
          print("TeacherMinute questionStatus polling error=\(error)")
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
        print("TeacherMinute questionStatus realtimeOverride questionId=\(questionId) status=\(realtimeResult.status)")
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
  var totalSpendText: String
  var lessonCount: Int
  var hasUnreadMessages: Bool
  var profileImageURL: String

  init(
    name: String = "Sarah Jenkins",
    searchState: StudentSearchState = .idle,
    activeQuestionText: String = "",
    activeConnectionFeeCents: Int = 0,
    selectedPricePerMinuteCents: Int = 50,
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
        purchaseSKU: nil
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
        purchaseSKU: nil
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
    self.questionId = "mock-lesson"
    self.pricingOptions = pricingOptions
    self.recentLessons = recentLessons
    self.totalTimeLearnedText = "36 min"
    self.totalSpendText = "$27.80"
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

  func viewAllLessons() {}

  func loadProfileIfNeeded() async {}

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
      teacherSharePercent: 75
    )
  }
}
