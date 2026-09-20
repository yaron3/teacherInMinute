//
//  EmailRewardViewModel.swift
//  teacher-minute
//
//  Drives the verify-your-email banner on both home screens. Verifying earns a
//  one-off welcome reward: free minutes for a student, a better earnings share
//  on the first taught minutes for a teacher. The backend decides eligibility
//  (functions/src/emailRewards.ts), including whether this mailbox has already
//  been rewarded under another address alias.
//

import SwiftUI
import Observation
import SkipFuse

struct EmailRewardDialog: Equatable {
  let title: String
  let message: String
}

@MainActor
@Observable
final class EmailRewardViewModel {
  var reward: EmailRewardStatus?
  var isWorking = false
  var dialog: EmailRewardDialog?
  /// Bumped when minutes or a bonus were just credited, so the owning screen
  /// can re-read the balance it shows.
  var grantVersion = 0

  let authService = AuthService()

  var showsVerifyBanner: Bool {
    reward?.status == .notVerified && offerDescription != nil
  }

  var showsTeacherBonus: Bool {
    guard let reward, reward.role == "teacher" else { return false }
    return reward.teacherBonusMinutesRemaining > 0
  }

  /// Checks quietly for a reward. Federated sign-ins are rewarded here with no
  /// action at all; an email account is rewarded on the first check after its
  /// link was followed.
  func refresh() async {
    guard !isWorking, !isSettled else { return }
    await claim(explicit: false)
  }

  /// Nothing further can change for this session. A teacher's bonus is never
  /// settled here, since lessons keep drawing it down.
  var isSettled: Bool {
    guard let reward else { return false }
    switch reward.status {
    case .claimedByOtherAccount:
      return true
    case .granted, .alreadyGranted:
      return reward.role == "student"
    case .notVerified, .notEligible, .unavailable:
      return false
    }
  }

  func checkVerificationTapped() async {
    guard !isWorking else { return }
    await claim(explicit: true)
  }

  func resendTapped() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await authService.sendEmailVerification()
      AnalyticsService.shared.logEvent(AnalyticsEvent.emailVerificationSent, parameters: ["source": "banner"])
      dialog = EmailRewardDialog(title: emailSentTitle, message: linkSentMessage)
    } catch {
      AnalyticsService.shared.recordError(error, context: "email_reward_resend")
      dialog = EmailRewardDialog(title: verifyEmailTitle, message: sendFailedMessage)
    }
  }

  func dismissDialog() {
    dialog = nil
  }

  func claim(explicit: Bool) async {
    isWorking = true
    defer { isWorking = false }
    let result: EmailRewardStatus
    do {
      result = try await FunctionsService.shared.claimEmailReward()
    } catch {
      logger.info("[EmailReward] claim failed: \(error.localizedDescription)")
      if explicit {
        dialog = EmailRewardDialog(title: verifyEmailTitle, message: checkFailedMessage)
      }
      return
    }
    reward = result

    switch result.status {
    case .granted:
      AnalyticsService.shared.logEvent(AnalyticsEvent.emailRewardGranted, parameters: ["role": result.role ?? ""])
      grantVersion += 1
      dialog = grantedDialog(for: result)
    case .notVerified:
      if explicit {
        dialog = EmailRewardDialog(title: notVerifiedTitle, message: notVerifiedMessage)
      }
    case .claimedByOtherAccount:
      AnalyticsService.shared.logEvent(AnalyticsEvent.emailRewardRejected, parameters: ["reason": result.status.rawValue])
      if explicit {
        dialog = EmailRewardDialog(title: verifyEmailTitle, message: alreadyClaimedMessage)
      }
    case .alreadyGranted, .notEligible, .unavailable:
      break
    }
  }

  func grantedDialog(for result: EmailRewardStatus) -> EmailRewardDialog {
    if result.role == "teacher" {
      return EmailRewardDialog(
        title: teacherGrantedTitle,
        message: teacherBonusText(percent: result.teacherSharePercent, minutes: result.teacherBonusMinutesRemaining)
      )
    }
    return EmailRewardDialog(
      title: studentGrantedTitle(minutes: result.studentMinutes),
      message: studentGrantedMessage
    )
  }

  /// The pitch shown on the banner, or nil when there is nothing to offer.
  var offerDescription: String? {
    guard let reward else { return nil }
    switch reward.role {
    case "student" where reward.studentMinutes > 0:
      return studentOfferText(minutes: reward.studentMinutes)
    case "teacher" where reward.teacherBonusMinutes > 0:
      return teacherOfferText(percent: reward.teacherSharePercent, minutes: reward.teacherBonusMinutes)
    default:
      return nil
    }
  }

  var teacherBonusDescription: String {
    guard let reward else { return "" }
    return teacherBonusText(percent: reward.teacherSharePercent, minutes: reward.teacherBonusMinutesRemaining)
  }

  var linkSentMessage: String {
    String(format: linkSentFormat, authService.currentUserEmail ?? "")
  }
}
