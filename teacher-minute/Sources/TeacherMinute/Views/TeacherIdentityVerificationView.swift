//
//  TeacherIdentityVerificationView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI
#if !os(Android)
@preconcurrency import PhotosUI
#else
import SkipBridge
#endif

@MainActor
struct TeacherIdentityVerificationView: View {
  @State var viewModel = TeacherIdentityVerificationViewModel()
  @Environment(\.appRouter) var router
  
#if os(Android)
  // Camera-vs-gallery chooser state for the Android upload flow.
  @State var showAndroidPhotoSourceDialog = false
  @State var androidPickTarget: UploadTarget = .governmentIDFront
#endif
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	ZStack {
	  ScrollView {
		VStack(alignment: .leading, spacing: 0) {
		  Text(viewModel.stepIndicatorText)
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(theme.secondaryText)
			.frame(maxWidth: .infinity)
		  

		  
//		  Text(LocalizationSupport.localized("To maintain a high-quality learning environment,\nwe need to verify your teaching credentials and\nidentity."))
//			.font(.system(size: 13))
//			.foregroundStyle(theme.secondaryText)
//			.lineSpacing(5)
//			.padding(.top, 8)
		  
		 // verificationStatus
		//	.padding(.top, 20)
		  
		  sectionTitle(viewModel.governmentIDSectionTitle)
			.padding(.top, 22)
		  
		  Text(RemoteConfigService.getLocalizedString(for: .teacherIdGovIdDescription, fallback: viewModel.governmentIDDescriptionFallback))
			.font(.system(size: 11))
			.foregroundStyle(theme.secondaryText)
			.lineSpacing(4)
			.padding(.top, 8)
		  
		  HStack(spacing: 12) {
#if !os(Android)
			let hasFront      = viewModel.hasGovernmentIDFront
			let frontSpinning = viewModel.isUploading(for: .governmentIDFront)
			PhotoSourceButton(viewModel: viewModel, onImageData: { data in
			  viewModel.handlePickedImage(data, for: .governmentIDFront)
			}) {
			  IDUploadBox(
				title: viewModel.frontSideLabel,
				isCompleted: hasFront,
				isUploading: frontSpinning,
				isMandatory: false,
				uploadingLabel: viewModel.uploadingLabel,
				requiredLabel: viewModel.requiredLowercaseLabel,
				action: {}
			  )
			}
#else
				Button {
				  androidPickTarget = .governmentIDFront
				  showAndroidPhotoSourceDialog = true
				} label: {
				  idFrontPickerLabel
				}
				.buttonStyle(.plain)
#endif
		  }
		  .padding(.top, 12)
		  
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
			Text(viewModel.submitBlockedHint)
			.font(.system(size: 11))
			.foregroundStyle(theme.primaryText)
			.padding(.top, 8)
		  }
		  
		  AuthPrimaryButton(
			title: viewModel.submitForReviewLabel,
			systemImage: "arrow.right",
			isEnabled: viewModel.canSubmit
		  ) {
			Task { @MainActor in
			  viewModel.submitForReview()
			}
		  }
		  .padding(.top, 24)
		  .padding(.bottom, 24)
		  
		  AuthPrimaryButton(
			title: viewModel.continueUploadLaterLabel,
			systemImage: "arrow.right",
			isEnabled: true
		  ) {
			Task { @MainActor in
			  viewModel.onSubmit?()
			}
		  }
		  .padding(.top, 24)
		}
		.padding(.horizontal, 18)
	  }
	  .background(Color(.systemBackground))
	  
	  // Full-screen spinner while checking Firestore on appear
	  if viewModel.isCheckingCompletion {
		theme.scrim.opacity(0.25).ignoresSafeArea()
		VStack(spacing: 14) {
		  ProgressView()
			.progressViewStyle(.circular)
			.scaleEffect(1.8)
			.tint(theme.primaryText)
		  Text(viewModel.checkingLabel)
			.font(.system(size: 14, weight: .medium))
			.foregroundStyle(theme.primaryText)
		}
	  }
	}
	.navigationBarTitleDisplayMode(.inline)
	.onboardingBackHandling(viewModel: viewModel)
	.onAppear {
	  viewModel.onSubmit = { router.push(.teacherSubjects) }
	  viewModel.checkAndAutoAdvance()
	}
	.navigationTitle(viewModel.screenTitle)
#if os(Android)
	.confirmationDialog(
	  viewModel.addPhotoDialogTitle,
	  isPresented: $showAndroidPhotoSourceDialog,
	  titleVisibility: .visible
	) {
	  Button(viewModel.takePhotoLabel) {
		pickAndUploadAndroidImage(for: androidPickTarget, source: .camera)
	  }
	  Button(viewModel.chooseFromLibraryLabel) {
		pickAndUploadAndroidImage(for: androidPickTarget, source: .gallery)
	  }
	  Button(viewModel.cancelLabel, role: .cancel) {}
	}
#endif

  }
  
  // MARK: - Picker label helpers (Android / preview)
  var credentialsPickerLabel: some View {
	UploadLargeBox(
	  title: viewModel.tapToUploadDocumentLabel,
	  subtitle: viewModel.uploadFormatsHint,
	  icon: "icloud.and.arrow.up.fill",
	  isCompleted: viewModel.hasTeachingCredentials,
	  isUploading: viewModel.isUploading(for: .teachingCredentials),
	  uploadingLabel: viewModel.uploadingLabel,
	  action: {}
	)
  }
  
  var idFrontPickerLabel: some View {
	IDUploadBox(title: viewModel.frontSideLabel, isCompleted: viewModel.hasGovernmentIDFront,
				isUploading: viewModel.isUploading(for: .governmentIDFront),
				isMandatory: true,
				uploadingLabel: viewModel.uploadingLabel,
				requiredLabel: viewModel.requiredLowercaseLabel, action: {})
  }
  
  var idBackPickerLabel: some View {
	IDUploadBox(title: viewModel.backSideLabel, isCompleted: viewModel.hasGovernmentIDBack,
				isUploading: viewModel.isUploading(for: .governmentIDBack),
				isMandatory: false,
				uploadingLabel: viewModel.uploadingLabel,
				requiredLabel: viewModel.requiredLowercaseLabel, action: {})
  }
  
  var selfiePickerLabel: some View {
	SelfieRow(isCompleted: viewModel.hasSelfie,
			  isUploading: viewModel.isUploading(for: .selfie),
			  uploadingLabel: viewModel.uploadingSelfieLabel,
			  takeSelfieLabel: viewModel.takeSelfieLabel,
			  lightingHint: viewModel.ensureGoodLightingHint, action: {})
  }
  
  // MARK: - Load picked image → upload
#if os(Android)
  enum AndroidPhotoSource {
	case camera
	case gallery
  }

  private func pickAndUploadAndroidImage(for target: UploadTarget, source: AndroidPhotoSource) {
	Task {
	  do {
		if source == .camera {
		  let cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
		  guard cameraState.isGranted else {
			viewModel.uploadError = viewModel.cameraAccessRequiredMessage
			return
		  }
		}
		logger.info("TeacherMinute Android image pick requested target=\(target) source=\(source)")
		let base64 = try await Task.detached(priority: .userInitiated) {
		  switch source {
		  case .camera:  return try AndroidImagePickerBridge.captureImageBase64()
		  case .gallery: return try AndroidImagePickerBridge.pickImageBase64()
		  }
		}.value
		logger.info("TeacherMinute Android image pick returned target=\(target) base64Length=\(base64.count)")
		guard !base64.isEmpty else {
		  logger.info("TeacherMinute Android image pick cancelled target=\(target)")
		  return
		}
		guard let data = Data(base64Encoded: base64) else {
		  viewModel.uploadError = viewModel.couldNotReadImageMessage
		  return
		}
		logger.info("TeacherMinute Android image decoded target=\(target) bytes=\(data.count)")
		viewModel.handlePickedImage(data, for: target)
	  } catch {
		logger.info("TeacherMinute Android image pick failed target=\(target) error=\(error)")
		viewModel.uploadError = error.localizedDescription
	  }
	}
  }
#endif
  
  // MARK: - Sub-views
  var verificationStatus: some View {
	VStack(alignment: .leading, spacing: 14) {
	  HStack {
		Text(viewModel.verificationStatusSectionTitle)
		  .font(.system(size: 11, weight: .bold))
		  .foregroundStyle(theme.primaryText)
		Spacer()
		Text(viewModel.verificationStatusLabel)
		  .font(.system(size: 11, weight: .medium))
		  .foregroundStyle(viewModel.canSubmit ? theme.positive : theme.primaryText)
		  .padding(.horizontal, 10)
		  .frame(height: 22)
		  .background((viewModel.canSubmit ? theme.positive : theme.controlDisabled).opacity(0.12))
		  .clipShape(Capsule())
	  }
	  StatusRow(title: viewModel.governmentIDFrontStatusTitle,
				isDone: viewModel.hasGovernmentIDFront,
				isMandatory: false,
				requirementLabel: viewModel.requirementLabel(isMandatory: false),
				alertMark: viewModel.alertMark)
	}
	.padding(16)
	.background(theme.cardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
	.shadow(color: theme.cardShadow.opacity(0.035), radius: 18, x: 0, y: 10)
  }
  
  var privacyBox: some View {
	HStack(alignment: .top, spacing: 12) {
	  PlatformIcon(
		systemName: "shield.lefthalf.filled",
		size: 18,
		weight: .semibold,
		color: theme.accent
	  )
	  VStack(alignment: .leading, spacing: 6) {
		Text(viewModel.privacyTitle)
		  .font(.system(size: 13, weight: .bold))
		  .foregroundStyle(theme.primaryText)
		Text(viewModel.privacyText)
		  .font(.system(size: 11))
		  .foregroundStyle(theme.secondaryText)
		  .lineSpacing(4)
	  }
	  Spacer()
	}
	.padding(16)
	.background(theme.accentBackground.opacity(0.45))
	.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
  
  var termsCheckbox: some View {
	Button {
	  viewModel.acceptedTerms.toggle()
	} label: {
	  HStack(alignment: .top, spacing: 10) {
		PlatformIcon(systemName: viewModel.acceptedTerms ? "checkmark.square.fill" : "square")
		  .font(.system(size: 18))
		  .foregroundStyle(viewModel.acceptedTerms ? theme.accent : theme.secondaryText)
		Text(viewModel.confirmDocumentsText)
		  .font(.system(size: 11))
		  .foregroundStyle(theme.secondaryText)
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
	  .foregroundStyle(theme.primaryText)
  }
}

// MARK: - StatusRow

struct StatusRow: View {
  let title: String
  let isDone: Bool
  let isMandatory: Bool
  let requirementLabel: String
  let alertMark: String
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	HStack(spacing: 12) {
	  Circle()
		.fill(theme.controlBorder)
		.frame(width: 18, height: 18)
		.overlay {
		  PlatformIcon(systemName: isDone ? "checkmark" : "circle.fill")
			.font(.system(size: 8, weight: .bold))
			.foregroundStyle(isDone ? theme.positive : theme.secondaryText)
		}
	  
	  Text(title)
		.font(.system(size: 12))
		.foregroundStyle(theme.secondaryText)
	  
	  if isMandatory && !isDone {
		Text(requirementLabel)
		  .font(.system(size: 9, weight: .semibold))
		  .foregroundStyle(theme.warning)
		  .padding(.horizontal, 6)
		  .padding(.vertical, 2)
		  .background(theme.warningBackground)
		  .clipShape(Capsule())
	  }
	  
	  Spacer()
	  
	  Circle()
		.fill(isDone ? theme.positive : theme.controlDisabled)
		.frame(width: 10, height: 10)
		.overlay {
		  if !isDone {
			Text(alertMark)
			  .font(.system(size: 7, weight: .bold))
			  .foregroundStyle(theme.primaryText)
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
  let uploadingLabel: String
  
  nonisolated init(title: String, subtitle: String, icon: String,
				   isCompleted: Bool, isUploading: Bool = false,
				   uploadingLabel: String,
				   action: @escaping @Sendable () -> Void = {}) {
	self.uploadingLabel = uploadingLabel
	self.title = title
	self.subtitle = subtitle
	self.icon = icon
	self.isCompleted = isCompleted
	self.isUploading = isUploading
	
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	VStack(spacing: 10) {
	  Circle()
		.fill(theme.accentBackground)
		.frame(width: 42, height: 42)
		.overlay {
		  if isUploading {
			ProgressView()
			  .progressViewStyle(.circular)
			  .tint(theme.accent)
		  } else {
			PlatformIcon(systemName: isCompleted ? "checkmark" : icon)
			  .font(.system(size: 16, weight: .bold))
			  .foregroundStyle(isCompleted ? theme.positive : theme.accent)
		  }
		}
	  
	  Text(isUploading ? uploadingLabel : title)
		.font(.system(size: 13, weight: .semibold))
		.foregroundStyle(theme.primaryText)
	  
	  Text(subtitle)
		.font(.system(size: 10))
		.foregroundStyle(theme.secondaryText)
	}
	.frame(maxWidth: .infinity)
	.frame(height: 116)
	.background(theme.cardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 14, style: .continuous)
		.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
		.foregroundStyle(theme.controlBorder)
	}
  }
}

// MARK: - IDUploadBox

struct IDUploadBox: View {
  let title: String
  let isCompleted: Bool
  let isUploading: Bool
  let isMandatory: Bool
  let uploadingLabel: String
  let requiredLabel: String
  
  nonisolated init(title: String, isCompleted: Bool,
				   isUploading: Bool = false, isMandatory: Bool = false,
				   uploadingLabel: String, requiredLabel: String,
				   action: @escaping @Sendable () -> Void = {}) {
	self.uploadingLabel = uploadingLabel
	self.requiredLabel = requiredLabel
	self.title = title
	self.isCompleted = isCompleted
	self.isUploading = isUploading
	self.isMandatory = isMandatory
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	VStack(spacing: 8) {
	  Circle()
		.fill(theme.accentBackground)
		.frame(width: 36, height: 36)
		.overlay {
		  if isUploading {
			ProgressView()
			  .progressViewStyle(.circular)
			  .tint(theme.accent)
		  } else {
			PlatformIcon(systemName: isCompleted ? "checkmark" : "person.text.rectangle")
			  .font(.system(size: 14, weight: .semibold))
			  .foregroundStyle(isCompleted ? theme.positive : theme.accent)
		  }
		}
	  
	  Text(isUploading ? uploadingLabel : title)
		.font(.system(size: 12, weight: .medium))
		.foregroundStyle(theme.primaryText)
	  
	  if isMandatory && !isCompleted && !isUploading {
		Text(requiredLabel)
		  .font(.system(size: 9, weight: .semibold))
		  .foregroundStyle(theme.warning)
		  .padding(.horizontal, 5)
		  .padding(.vertical, 2)
		  .background(theme.warningBackground)
		  .clipShape(Capsule())
	  }
	}
	.frame(maxWidth: .infinity)
	.frame(height: 90)
	.background(theme.cardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 14, style: .continuous)
		.strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
		.foregroundStyle(isMandatory && !isCompleted ? theme.warning : theme.controlBorder)
	}
  }
}

// MARK: - SelfieRow

struct SelfieRow: View {
  let isCompleted: Bool
  let isUploading: Bool
  let uploadingLabel: String
  let takeSelfieLabel: String
  let lightingHint: String
  
  nonisolated init(isCompleted: Bool, isUploading: Bool = false,
				   uploadingLabel: String, takeSelfieLabel: String,
				   lightingHint: String,
				   action: @escaping @Sendable () -> Void = {}) {
	self.uploadingLabel = uploadingLabel
	self.takeSelfieLabel = takeSelfieLabel
	self.lightingHint = lightingHint
	self.isCompleted = isCompleted
	self.isUploading = isUploading
  }
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	HStack(spacing: 14) {
	  RoundedRectangle(cornerRadius: 12, style: .continuous)
		.fill(theme.fieldBackground)
		.frame(width: 42, height: 42)
		.overlay {
		  if isUploading {
			ProgressView()
			  .progressViewStyle(.circular)
			  .tint(theme.primaryText)
		  } else {
			PlatformIcon(systemName: isCompleted ? "checkmark" : "camera.fill")
			  .foregroundStyle(isCompleted ? theme.positive : theme.primaryText)
		  }
		}
	  
	  VStack(alignment: .leading, spacing: 4) {
		Text(isUploading ? uploadingLabel : takeSelfieLabel)
		  .font(.system(size: 13, weight: .semibold))
		  .foregroundStyle(theme.primaryText)
		
		Text(lightingHint)
		  .font(.system(size: 11))
		  .foregroundStyle(theme.secondaryText)
	  }
	  
	  Spacer()
	  
	  PlatformIcon(
		systemName: "chevron.right",
		size: 12,
		weight: .semibold,
		color: theme.secondaryText
	  )
	}
	.padding(14)
	.background(theme.cardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 16, style: .continuous)
		.stroke(theme.controlBorder, lineWidth: 1)
	}
  }
}

#if os(Android)
private enum AndroidImagePickerBridge {
  private static let managerClass = try! JClass(name: "teacher/minute/AndroidImagePickerManager")
  private static let pickImageBase64Method = managerClass.getStaticMethodID(
	name: "pickImageBase64",
	sig: "()Ljava/lang/String;"
  )!
  private static let captureImageBase64Method = managerClass.getStaticMethodID(
	name: "captureImageBase64",
	sig: "()Ljava/lang/String;"
  )!

  static func pickImageBase64() throws -> String {
	try jniContext {
	  try managerClass.callStatic(
		method: pickImageBase64Method,
		options: [.kotlincompat],
		args: []
	  )
	}
  }

  static func captureImageBase64() throws -> String {
	try jniContext {
	  try managerClass.callStatic(
		method: captureImageBase64Method,
		options: [.kotlincompat],
		args: []
	  )
	}
  }
}
#endif


#if os(ios)
#Preview {
  termsCheckbox()
}
#endif
