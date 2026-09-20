//
//  CompleteProfileViewModel.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 07/05/2026.
//

import SwiftUI
import Observation
import SkipFuse

#if !os(Android)
import FirebaseAuth
#else
import SkipFirebaseAuth
#endif

@Observable
@MainActor
final class CompleteProfileViewModel {
  let role: AuthRole
  var fullName = ""
  var phoneNumber = ""
  var grade = ""

  /// How the teacher would like to be paid, or `nil` while they have not said.
  /// Only the choice is collected here — no account numbers — and it is kept
  /// locally (PayoutMethodPreferenceStore) so the payout form opens on the
  /// matching tab when they come to fill the details in.
  var payoutMethodType: PayoutMethodType?
  /// The destinations to offer. PayPal is behind a Remote Config flag, so a
  /// teacher is never offered a destination Earnings would not accept.
  var availablePayoutMethodTypes: [PayoutMethodType] = [.bank, .bit]
  
  var isLoading = false
  var isCheckingCompletion = true
  var showMissingPayoutInfoConfirmation = false
  var errorMessage: String?
  var shouldShowPermissionsOnContinue = true
  var onContinue: (() -> Void)?
  
  let grades: [String] = (1...12).map { LocalizationSupport.localized("Grade \($0)") } + [LocalizationSupport.localized("College"), LocalizationSupport.localized("Adult Learner")]
  
  /// Phone is optional for students and required for teachers, but a number
  /// that was typed has to be a real one either way — a teacher's is what the
  /// Bit payout is later sent to.
  var isPhoneValid: Bool {
	let trimmedPhone = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
	if trimmedPhone.isEmpty {
	  return role == .student
	}
	return trimmedPhone.isValidPhoneNumber
  }

  /// Stays quiet on an untouched field so the error only appears once there is
  /// something wrong to point at.
  var showsPhoneError: Bool {
	!phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPhoneValid
  }

  var phoneErrorMessage: String {
	LocalizationSupport.localized("Enter a valid phone number.")
  }

  var canContinue: Bool {
	let hasName = !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
	return !isLoading && hasName && isPhoneValid
  }

  /// Tapping the chosen destination again clears it — picking one now is
  /// optional, and there has to be a way back out of a stray tap.
  func selectPayoutMethodType(_ type: PayoutMethodType) {
	payoutMethodType = payoutMethodType == type ? nil : type
  }
  
  init(role: AuthRole) {
	self.role = role
  }
  
  // MARK: - Auto-advance
  
  func checkAndAutoAdvance() {
	Task {
	  defer { isCheckingCompletion = false }
	  guard let uid = Auth.auth().currentUser?.uid else { return }
	  let data = (try? await UserService.shared.fetchRaw(uid: uid)) ?? [:]
	  let savedName  = data["fullName"]    as? String ?? ""
	  let savedPhone = data["phoneNumber"] as? String ?? ""
	  let hasName  = !savedName.isEmpty
	  let hasPhone = !savedPhone.isEmpty
	  let hasProfile = role == .teacher
				? (hasName && hasPhone)
				: hasName
	  if hasProfile {
			fullName    = savedName
			phoneNumber = savedPhone
			grade       = data["grade"]       as? String ?? ""
				shouldShowPermissionsOnContinue = false
				onContinue?()
	  } else {
			// Only for the teacher who is staying on the screen: the picker is
			// theirs alone, and a Remote Config read would otherwise sit in
			// front of an auto-advance that never shows it.
			if role == .teacher {
			  payoutMethodType = payoutMethodType ?? PayoutMethodPreferenceStore.preferredTypeForCurrentUser()
			  await loadAvailablePayoutMethodTypes()
			}
			if fullName.isEmpty {
			  if hasName {
				fullName = savedName
			  } else {
				let providerName = (Auth.auth().currentUser?.displayName ?? "")
				  .trimmingCharacters(in: .whitespacesAndNewlines)
				if !providerName.isEmpty {
				  fullName = providerName
				}
			  }
			}
			if phoneNumber.isEmpty && hasPhone {
			  phoneNumber = savedPhone
			}
			if grade.isEmpty {
			  let savedGrade = data["grade"] as? String ?? ""
			  if !savedGrade.isEmpty {
				grade = savedGrade
			  }
			}
	  }
	}
  }
  
  /// Drops PayPal from the picker unless Remote Config offers it as a payout
  /// destination — the same gate Earnings applies to its own picker.
  private func loadAvailablePayoutMethodTypes() async {
	let isPayPalEnabled = await SettingsRemoteConfigService.shared.fetchIsPayPalPayoutEnabled()
	availablePayoutMethodTypes = PayoutMethodType.allCases.filter { type in
	  type != .paypal || isPayPalEnabled
	}
	// A choice made before the flag was turned off would otherwise stay
	// selected on a tab that is no longer on screen.
	if let chosen = payoutMethodType, !availablePayoutMethodTypes.contains(chosen) {
	  payoutMethodType = nil
	}
  }

  // MARK: - Save & continue
  
  func continueFlow() {
	guard canContinue else { return }
	if role == .teacher && payoutMethodType == nil {
	  showMissingPayoutInfoConfirmation = true
	  return
	}
	saveAndContinue()
  }

  func continueWithoutPayoutInfo() {
	showMissingPayoutInfoConfirmation = false
	saveAndContinue()
  }

  private func saveAndContinue() {
	isLoading = true

	// Store the canonical local form ("0521234567") whatever spelling was
	// typed, so the payout sheet's "use my profile number" shortcut hands the
	// backend a number it already accepts.
	phoneNumber = phoneNumber.normalizedPhoneNumber
	// `canContinue` checks the trimmed name, so store the trimmed one too —
	// otherwise a name typed with a stray space is saved with it.
	fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)

	Task {
	  do {
		guard let user = Auth.auth().currentUser else {
		  errorMessage = "No authenticated user found."
		  isLoading = false
		  return
		}

		let profile = UserProfile(
		  uid:         user.uid,
		  email:       user.email ?? "",
		  fullName:    fullName,
			  phoneNumber: phoneNumber,
			  dateOfBirth: nil,
			  grade:       grade,
			  role:        role.rawValue,
			  createdAt:   Date()
			)
		
		try await UserService.shared.saveProfile(profile)
		// Local, not part of the profile: it is a preference until real payout
		// details exist, and those are the backend's copy to hold.
		if role == .teacher {
		  PayoutMethodPreferenceStore.setPreferredTypeForCurrentUser(payoutMethodType)
		}
		AnalyticsService.shared.logEvent(AnalyticsEvent.profileCompleted, parameters: [
		  "role": role.rawValue,
		  "has_grade": !grade.isEmpty,
		  "has_payout_method": payoutMethodType != nil
			])
			isLoading = false
			shouldShowPermissionsOnContinue = true
			onContinue?()
	  } catch {
		AnalyticsService.shared.recordError(error, context: "saveProfile")
		errorMessage = error.localizedDescription
		isLoading = false
	  }
	}
  }
}
