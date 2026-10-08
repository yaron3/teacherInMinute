//
//  VerifyEmailViewModel.swift
//  teacher-minute
//
//  The verify-your-email step at the end of a student's sign-up. Signing up
//  (or changing the address on the profile step) has already emailed a link;
//  this step waits for it to be followed, then claims the welcome reward the
//  home screen's banner would otherwise offer. "Not now" leaves that banner to
//  do it later.
//

import SwiftUI
import Observation
import SkipFuse

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

@MainActor
@Observable
final class VerifyEmailViewModel {
  /// The address the link was sent to. After a change on the profile step it
  /// is not the account's address yet — it becomes so when the link is opened.
  let email: String
  var isWorking = false
  var dialog: EmailRewardDialog?
  /// Free minutes verifying earns, once the backend has said; 0 while there
  /// is no offer.
  var rewardMinutes = 0

  /// Verification is done, so dismissing the dialog moves on.
  private var finishesAfterDialog = false
  /// The session ended — following a change-of-address link revokes it — so
  /// dismissing the dialog goes to the login form.
  private var sessionEnded = false
  /// The step has moved on. The link coming back and the quiet check on
  /// return both conclude it; only the first may navigate.
  private var hasFinished = false

  var onFinished: (() -> Void)?
  var onSessionEnded: (() -> Void)?

  let authService = AuthService()

  init(email: String) {
    self.email = email
  }

  /// Reads the offer quietly. An account that is somehow verified already is
  /// rewarded and moved on.
  func load() async {
    guard let result = try? await FunctionsService.shared.claimEmailReward() else { return }
    switch result.status {
    case .granted:
      AnalyticsService.shared.logEvent(AnalyticsEvent.emailRewardGranted, parameters: ["role": result.role ?? ""])
      finish(withDialog: grantedDialog(minutes: result.studentMinutes))
    case .notVerified:
      rewardMinutes = result.studentMinutes
    case .promotionEnded:
      rewardMinutes = 0
    case .alreadyGranted, .claimedByOtherAccount, .notEligible, .unavailable:
      break
    }
  }

  /// Coming back to the app another way than the link — say the link was
  /// opened on a computer: moves on if the address is verified by now, and
  /// says nothing if it is not.
  func checkQuietly() async {
    guard !isWorking, dialog == nil else { return }
    await check()
  }

  func resendTapped() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      let isOwnAddress = email.lowercased() == authService.currentUserEmail?.lowercased()
      try await FunctionsService.shared.sendVerificationEmail(email: isOwnAddress ? nil : email)
      AnalyticsService.shared.logEvent(AnalyticsEvent.emailVerificationSent, parameters: ["source": "signup_verify_step"])
      dialog = EmailRewardDialog(title: emailSentTitle, message: linkSentMessage)
    } catch {
      AnalyticsService.shared.recordError(error, context: "signup_verify_resend")
      dialog = EmailRewardDialog(title: verifyEmailTitle, message: sendFailedMessage)
    }
  }

  func notNowTapped() {
    AnalyticsService.shared.logEvent(AnalyticsEvent.emailVerifySkipped)
    moveOn()
  }

  /// The verification link opened the app. The backend has verified the
  /// address and claimed the reward, and the app root says how that went, so
  /// this step only moves on.
  func linkVerifiedEmail() {
    dialog = nil
    moveOn()
  }

  private func moveOn() {
    guard !hasFinished else { return }
    hasFinished = true
    onFinished?()
  }

  func dismissDialog() {
    dialog = nil
    if sessionEnded {
      onSessionEnded?()
    } else if finishesAfterDialog {
      moveOn()
    }
  }

  private func check() async {
    isWorking = true
    defer { isWorking = false }

    let verified: Bool
    do {
      verified = try await authService.isEmailVerified(email)
    } catch {
      if Auth.auth().currentUser == nil {
        sessionEnded = true
        dialog = EmailRewardDialog(title: emailChangedTitle, message: logInAgainMessage)
      }
      return
    }
    guard verified else { return }

    AnalyticsService.shared.logEvent(AnalyticsEvent.emailVerifyConfirmed)
    let result = try? await FunctionsService.shared.claimEmailReward()
    if let result, result.status == .granted {
      AnalyticsService.shared.logEvent(AnalyticsEvent.emailRewardGranted, parameters: ["role": result.role ?? ""])
      finish(withDialog: grantedDialog(minutes: result.studentMinutes))
    } else if let result, result.status == .promotionEnded {
      finish(withDialog: EmailRewardDialog(title: emailVerifiedTitle, message: promotionEndedMessage))
    } else {
      if let result, result.status == .claimedByOtherAccount {
        AnalyticsService.shared.logEvent(AnalyticsEvent.emailRewardRejected, parameters: ["reason": result.status.rawValue])
      }
      moveOn()
    }
  }

  private func finish(withDialog dialog: EmailRewardDialog) {
    finishesAfterDialog = true
    self.dialog = dialog
  }

  private func grantedDialog(minutes: Int) -> EmailRewardDialog {
    EmailRewardDialog(title: grantedTitle(minutes: minutes), message: grantedMessage)
  }
}
