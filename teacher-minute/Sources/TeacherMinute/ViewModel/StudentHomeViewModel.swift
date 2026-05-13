//
//  StudentHomeViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
import Observation
import Foundation

// MARK: - Search State

enum StudentSearchState {
  case idle
  case searching(questionId: String)
  case matched(questionId: String, liveKitRoom: String, liveKitToken: String)
  case noMatch
  case error(String)
}

// MARK: - Supporting Models

struct PricingOption: Identifiable {
  let id = UUID()
  let name: String
  let price: String
  let description: String
  let isHighlighted: Bool
}

struct RecentLesson: Identifiable {
  let id = UUID()
  let title: String
  let teacher: String
  let time: String
  let duration: String
}

// MARK: - ViewModel

@Observable
@MainActor
final class StudentHomeViewModel {

  var name = "Sarah Jenkins"
  var searchState: StudentSearchState = .idle

  let pricingOptions = [
    PricingOption(
      name: "Standard",
      price: "$0.50",
      description: "Verified tutors for algebra, geometry, and basic calculus.",
      isHighlighted: false
    ),
    PricingOption(
      name: "Expert",
      price: "$1.20",
      description: "Advanced degree tutors for college-level help.",
      isHighlighted: true
    ),
  ]

  let recentLessons = [
    RecentLesson(title: "Calculus Help", teacher: "with Mr. Davis",
                 time: "Today, 2:30 PM", duration: "14 mins"),
    RecentLesson(title: "Algebra II", teacher: "with Ms. Chen",
                 time: "Yesterday", duration: "22 mins"),
  ]

  private var pollingTask: Task<Void, Never>?

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

  func selectTier(_ option: PricingOption) {}
  func viewAllLessons() {}

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
}
