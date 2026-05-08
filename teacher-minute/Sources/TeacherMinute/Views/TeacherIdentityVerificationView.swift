//
//  TeacherIdentityVerificationView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
#if !os(Android)
@preconcurrency import PhotosUI
#endif

@MainActor
struct TeacherIdentityVerificationView: View {
  @State var viewModel = TeacherIdentityVerificationViewModel()
  @Environment(\.appRouter) var router
  
#if !os(Android)
  // Separate state per slot — fixes back-side onChange not firing when same item reused
  @State private var credentialsItem: PhotosPickerItem?
  @State private var idFrontItem:     PhotosPickerItem?
  @State private var idBackItem:      PhotosPickerItem?
  @State private var selfieItem:      PhotosPickerItem?
#endif
  
  var body: some View {
	ZStack {
	  ScrollView {
		VStack(alignment: .leading, spacing: 0) {
		  Text("Step 1 of 2")
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(Color.authSecondaryText)
			.frame(maxWidth: .infinity)
		  
		  Text("Verify Your Identity")
			.font(.system(size: 26, weight: .bold))
			.foregroundStyle(Color.authPrimaryText)
			.padding(.top, 20)
		  
		  Text("To maintain a high-quality learning environment,\nwe need to verify your teaching credentials and\nidentity.")
			.font(.system(size: 13))
			.foregroundStyle(Color.authSecondaryText)
			.lineSpacing(5)
			.padding(.top, 8)
		  
		  verificationStatus
			.padding(.top, 20)
		  
		  sectionTitle("Teaching Credentials")
			.padding(.top, 22)
		  
		  Text("Upload your degree, teaching license, or relevant\ncertifications.")
			.font(.system(size: 11))
			.foregroundStyle(Color.authSecondaryText)
			.lineSpacing(4)
			.padding(.top, 8)
		  
#if !os(Android)
		  let hasCredentials      = viewModel.hasTeachingCredentials
		  let credentialsSpinning = viewModel.isUploading(for: .teachingCredentials)
		  PhotosPicker(selection: $credentialsItem,
					   matching: .any(of: [.images, .livePhotos])) {
			UploadLargeBox(
			  title: "Tap to upload document",
			  subtitle: "PDF, JPG or PNG (Max 5MB)",
			  icon: "icloud.and.arrow.up.fill",
			  isCompleted: hasCredentials,
			  isUploading: credentialsSpinning,
			  action: {}
			)
		  }
					   .onChange(of: credentialsItem) { _, item in
						 MainActor.assumeIsolated {
						   loadAndUpload(item, for: .teachingCredentials)
						 }
					   }
					   .padding(.top, 12)
#else
		  credentialsPickerLabel
#endif
		  
		  sectionTitle("Government ID")
			.padding(.top, 22)
		  
		  Text("Upload a clear photo of your passport, driver's license,\nor national ID.")
			.font(.system(size: 11))
			.foregroundStyle(Color.authSecondaryText)
			.lineSpacing(4)
			.padding(.top, 8)
		  
		  HStack(spacing: 12) {
#if !os(Android)
			let hasFront      = viewModel.hasGovernmentIDFront
			let frontSpinning = viewModel.isUploading(for: .governmentIDFront)
			let hasBack       = viewModel.hasGovernmentIDBack
			let backSpinning  = viewModel.isUploading(for: .governmentIDBack)
			PhotosPicker(selection: $idFrontItem, matching: .images) {
			  IDUploadBox(
				title: "Front Side",
				isCompleted: hasFront,
				isUploading: frontSpinning,
				isMandatory: true,
				action: {}
			  )
			}
			.onChange(of: idFrontItem) { _, item in
			  MainActor.assumeIsolated { loadAndUpload(item, for: .governmentIDFront) }
			}
			
			PhotosPicker(selection: $idBackItem, matching: .images) {
			  IDUploadBox(
				title: "Back Side",
				isCompleted: hasBack,
				isUploading: backSpinning,
				isMandatory: false,
				action: {}
			  )
			}
			.onChange(of: idBackItem) { _, item in
			  MainActor.assumeIsolated { loadAndUpload(item, for: .governmentIDBack) }
			}
#else
			idFrontPickerLabel
			idBackPickerLabel
#endif
		  }
		  .padding(.top, 12)
		  
		  sectionTitle("Selfie Verification")
			.padding(.top, 22)
		  
		  Text("Take a clear selfie to match with your Government ID.")
			.font(.system(size: 11))
			.foregroundStyle(Color.authSecondaryText)
			.padding(.top, 8)
		  
#if !os(Android)
		  let hasSelfie      = viewModel.hasSelfie
		  let selfieSpinning = viewModel.isUploading(for: .selfie)
		  PhotosPicker(selection: $selfieItem, matching: .images) {
			SelfieRow(
			  isCompleted: hasSelfie,
			  isUploading: selfieSpinning,
			  action: {}
			)
		  }
		  .onChange(of: selfieItem) { _, item in
			MainActor.assumeIsolated {
			  loadAndUpload(item, for: .selfie)
			}
		  }
		  .padding(.top, 12)
#else
		  selfiePickerLabel
#endif
		  
		  privacyBox
			.padding(.top, 24)
		  
		  termsCheckbox
			.padding(.top, 22)
		  
		  if let err = viewModel.uploadError {
			Text(err)
			  .font(.system(size: 12))
			  .foregroundStyle(.red)
			  .padding(.top, 8)
		  }
		  
		  // Hint when terms not accepted or front side missing
		  if !viewModel.canSubmit && viewModel.uploadingTarget == nil {
			Text(viewModel.hasGovernmentIDFront
				 ? "Accept the terms to continue"
				 : "Upload the front side of your ID to continue")
			.font(.system(size: 11))
			.foregroundStyle(Color.authOrange)
			.padding(.top, 8)
		  }
		  
		  AuthPrimaryButton(
			title: "Submit for Review",
			systemImage: "arrow.right",
			isEnabled: viewModel.canSubmit
		  ) {
			viewModel.submitForReview()
		  }
		  .padding(.top, 24)
		  .padding(.bottom, 24)
		}
		.padding(.horizontal, 18)
	  }
	  .background(Color(.systemBackground))
	  
	  // Full-screen spinner while checking Firestore on appear
	  if viewModel.isCheckingCompletion {
		Color.black.opacity(0.25).ignoresSafeArea()
		VStack(spacing: 14) {
		  ProgressView()
			.progressViewStyle(.circular)
			.scaleEffect(1.8)
			.tint(.white)
		  Text("Checking…")
			.font(.system(size: 14, weight: .medium))
			.foregroundStyle(.white)
		}
	  }
	}
	.navigationBarTitleDisplayMode(.inline)
	.onAppear {
	  viewModel.onSubmit = { router.push(.teacherSubjects) }
	  viewModel.checkAndAutoAdvance()
	}
  }
  
  // MARK: - Picker label helpers (Android / preview)
  var credentialsPickerLabel: some View {
	UploadLargeBox(
	  title: "Tap to upload document",
	  subtitle: "PDF, JPG or PNG (Max 5MB)",
	  icon: "icloud.and.arrow.up.fill",
	  isCompleted: viewModel.hasTeachingCredentials,
	  isUploading: viewModel.isUploading(for: .teachingCredentials),
	  action: {}
	)
  }
  
  var idFrontPickerLabel: some View {
	IDUploadBox(title: "Front Side", isCompleted: viewModel.hasGovernmentIDFront,
				isUploading: viewModel.isUploading(for: .governmentIDFront),
				isMandatory: true, action: {})
  }
  
  var idBackPickerLabel: some View {
	IDUploadBox(title: "Back Side", isCompleted: viewModel.hasGovernmentIDBack,
				isUploading: viewModel.isUploading(for: .governmentIDBack),
				isMandatory: false, action: {})
  }
  
  var selfiePickerLabel: some View {
	SelfieRow(isCompleted: viewModel.hasSelfie,
			  isUploading: viewModel.isUploading(for: .selfie), action: {})
  }
  
  // MARK: - Load PhotosPickerItem → Data → upload
#if !os(Android)
  private func loadAndUpload(_ item: PhotosPickerItem?, for target: UploadTarget) {
	guard let item else { return }
	Task {
	  if let data = try? await item.loadTransferable(type: Data.self) {
		viewModel.handlePickedImage(data, for: target)
	  }
	}
  }
#endif
  
  // MARK: - Sub-views
  var verificationStatus: some View {
	VStack(alignment: .leading, spacing: 14) {
	  HStack {
		Text("VERIFICATION STATUS")
		  .font(.system(size: 11, weight: .bold))
		  .foregroundStyle(Color.authPrimaryText)
		Spacer()
		Text(viewModel.canSubmit ? "Ready" : "Incomplete")
		  .font(.system(size: 11, weight: .medium))
		  .foregroundStyle(viewModel.canSubmit ? Color.authGreen : Color.authOrange)
		  .padding(.horizontal, 10)
		  .frame(height: 22)
		  .background((viewModel.canSubmit ? Color.authGreen : Color.authOrange).opacity(0.12))
		  .clipShape(Capsule())
	  }
	  StatusRow(title: "Teaching Credentials", isDone: viewModel.hasTeachingCredentials, isMandatory: false)
	  StatusRow(title: "Government ID – Front", isDone: viewModel.hasGovernmentIDFront, isMandatory: true)
	  StatusRow(title: "Government ID – Back",  isDone: viewModel.hasGovernmentIDBack,  isMandatory: false)
	  StatusRow(title: "Selfie Verification",   isDone: viewModel.hasSelfie,            isMandatory: false)
	}
	.padding(16)
	.background(.white)
	.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	.shadow(color: .black.opacity(0.035), radius: 18, x: 0, y: 10)
  }
  
  var privacyBox: some View {
	HStack(alignment: .top, spacing: 12) {
	  Image(systemName: "shield.lefthalf.filled")
		.font(.system(size: 18, weight: .semibold))
		.foregroundStyle(Color.authPurple)
	  VStack(alignment: .leading, spacing: 6) {
		Text("Your Privacy Matters")
		  .font(.system(size: 13, weight: .bold))
		  .foregroundStyle(Color.authPrimaryText)
		Text("Your documents are securely encrypted and\nonly used for verification purposes. They will\nnot be shared publicly on your profile.")
		  .font(.system(size: 11))
		  .foregroundStyle(Color.authSecondaryText)
		  .lineSpacing(4)
	  }
	  Spacer()
	}
	.padding(16)
	.background(Color.authPurpleSoft.opacity(0.45))
	.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
  
  var termsCheckbox: some View {
	Button {
	  viewModel.acceptedTerms.toggle()
	} label: {
	  HStack(alignment: .top, spacing: 10) {
		Image(systemName: viewModel.acceptedTerms ? "checkmark.square.fill" : "square")
		  .font(.system(size: 18))
		  .foregroundStyle(viewModel.acceptedTerms ? Color.authPink : Color.authIcon)
		Text("I confirm that the uploaded documents are\nauthentic and belong to me. I agree to the\nVerification Terms.")
		  .font(.system(size: 11))
		  .foregroundStyle(Color.authSecondaryText)
		  .lineSpacing(4)
		  .multilineTextAlignment(.leading)
		Spacer()
	  }
	}
	.buttonStyle(.plain)
  }
  
  func sectionTitle(_ title: String) -> some View {
	Text(title)
	  .font(.system(size: 15, weight: .bold))
	  .foregroundStyle(Color.authPrimaryText)
  }
}

// MARK: - StatusRow

struct StatusRow: View {
  let title: String
  let isDone: Bool
  let isMandatory: Bool
  
  var body: some View {
	HStack(spacing: 12) {
	  Circle()
		.fill(Color.authFieldBorder)
		.frame(width: 18, height: 18)
		.overlay {
		  Image(systemName: isDone ? "checkmark" : "circle.fill")
			.font(.system(size: 8, weight: .bold))
			.foregroundStyle(isDone ? Color.authGreen : Color.authIcon)
		}
	  
	  Text(title)
		.font(.system(size: 12))
		.foregroundStyle(Color.authSecondaryText)
	  
	  if isMandatory && !isDone {
		Text("required")
		  .font(.system(size: 9, weight: .semibold))
		  .foregroundStyle(Color.authOrange)
		  .padding(.horizontal, 6)
		  .padding(.vertical, 2)
		  .background(Color.authOrange.opacity(0.12))
		  .clipShape(Capsule())
	  }
	  
	  Spacer()
	  
	  Circle()
		.fill(isDone ? Color.authGreen : Color.authOrange)
		.frame(width: 10, height: 10)
		.overlay {
		  if !isDone {
			Text("!")
			  .font(.system(size: 7, weight: .bold))
			  .foregroundStyle(.white)
		  }
		}
	}
  }
}

// MARK: - UploadLargeBox

struct UploadLargeBox: View {
  let title: String
  let subtitle: String
  let icon: String
  let isCompleted: Bool
  let isUploading: Bool
  
  nonisolated init(title: String, subtitle: String, icon: String,
				   isCompleted: Bool, isUploading: Bool = false,
				   action: @escaping @Sendable () -> Void = {}) {
	self.title = title
	self.subtitle = subtitle
	self.icon = icon
	self.isCompleted = isCompleted
	self.isUploading = isUploading
  }
  
  var body: some View {
	VStack(spacing: 10) {
	  Circle()
		.fill(Color.authPinkSoft)
		.frame(width: 42, height: 42)
		.overlay {
		  if isUploading {
			ProgressView()
			  .progressViewStyle(.circular)
			  .tint(Color.authPink)
		  } else {
			Image(systemName: isCompleted ? "checkmark" : icon)
			  .font(.system(size: 16, weight: .bold))
			  .foregroundStyle(isCompleted ? Color.authGreen : Color.authPink)
		  }
		}
	  
	  Text(isUploading ? "Uploading…" : title)
		.font(.system(size: 13, weight: .semibold))
		.foregroundStyle(Color.authPrimaryText)
	  
	  Text(subtitle)
		.font(.system(size: 10))
		.foregroundStyle(Color.authSecondaryText)
	}
	.frame(maxWidth: .infinity)
	.frame(height: 116)
	.background(.white)
	.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 14, style: .continuous)
		.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
		.foregroundStyle(Color.authFieldBorder)
	}
  }
}

// MARK: - IDUploadBox

struct IDUploadBox: View {
  let title: String
  let isCompleted: Bool
  let isUploading: Bool
  let isMandatory: Bool
  
  nonisolated init(title: String, isCompleted: Bool,
				   isUploading: Bool = false, isMandatory: Bool = false,
				   action: @escaping @Sendable () -> Void = {}) {
	self.title = title
	self.isCompleted = isCompleted
	self.isUploading = isUploading
	self.isMandatory = isMandatory
  }
  
  var body: some View {
	VStack(spacing: 8) {
	  Circle()
		.fill(Color.authPurpleSoft)
		.frame(width: 36, height: 36)
		.overlay {
		  if isUploading {
			ProgressView()
			  .progressViewStyle(.circular)
			  .tint(Color.authPurple)
		  } else {
			Image(systemName: isCompleted ? "checkmark" : "person.text.rectangle")
			  .font(.system(size: 14, weight: .semibold))
			  .foregroundStyle(isCompleted ? Color.authGreen : Color.authPurple)
		  }
		}
	  
	  Text(isUploading ? "Uploading…" : title)
		.font(.system(size: 12, weight: .medium))
		.foregroundStyle(Color.authPrimaryText)
	  
	  if isMandatory && !isCompleted && !isUploading {
		Text("required")
		  .font(.system(size: 9, weight: .semibold))
		  .foregroundStyle(Color.authOrange)
		  .padding(.horizontal, 5)
		  .padding(.vertical, 2)
		  .background(Color.authOrange.opacity(0.12))
		  .clipShape(Capsule())
	  }
	}
	.frame(maxWidth: .infinity)
	.frame(height: 90)
	.background(.white)
	.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 14, style: .continuous)
		.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
		.foregroundStyle(isMandatory && !isCompleted ? Color.authOrange.opacity(0.5) : Color.authFieldBorder)
	}
  }
}

// MARK: - SelfieRow

struct SelfieRow: View {
  let isCompleted: Bool
  let isUploading: Bool
  
  nonisolated init(isCompleted: Bool, isUploading: Bool = false,
				   action: @escaping @Sendable () -> Void = {}) {
	self.isCompleted = isCompleted
	self.isUploading = isUploading
  }
  
  var body: some View {
	HStack(spacing: 14) {
	  RoundedRectangle(cornerRadius: 12, style: .continuous)
		.fill(Color.authFieldBackground)
		.frame(width: 42, height: 42)
		.overlay {
		  if isUploading {
			ProgressView()
			  .progressViewStyle(.circular)
			  .tint(Color.authPrimaryText)
		  } else {
			Image(systemName: isCompleted ? "checkmark" : "camera.fill")
			  .foregroundStyle(isCompleted ? Color.authGreen : Color.authPrimaryText)
		  }
		}
	  
	  VStack(alignment: .leading, spacing: 4) {
		Text(isUploading ? "Uploading selfie…" : "Take Selfie")
		  .font(.system(size: 13, weight: .semibold))
		  .foregroundStyle(Color.authPrimaryText)
		
		Text("Ensure good lighting")
		  .font(.system(size: 11))
		  .foregroundStyle(Color.authSecondaryText)
	  }
	  
	  Spacer()
	  
	  Image(systemName: "chevron.right")
		.font(.system(size: 12, weight: .semibold))
		.foregroundStyle(Color.authIcon)
	}
	.padding(14)
	.background(.white)
	.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 16, style: .continuous)
		.stroke(Color.authFieldBorder, lineWidth: 1)
	}
  }
}
