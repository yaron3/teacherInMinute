//
//  ProfileView.swift
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

struct ProfileView: View {
  @State var viewModel: ProfileViewModel
  @State var isShowingProfileEditor = false
  @State var isShowingSubjectEditor = false
  @State var isShowingDocuments = false
  @State var hasProfileDataForDisplay = false
  @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
#if os(Android)
  @State var showAndroidPhotoSourceDialog = false
#endif
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  init(viewModel: ProfileViewModel = ProfileViewModel()) {
	self._viewModel = State(initialValue: viewModel)
  }
  var body: some View {
	ScrollView(.vertical, showsIndicators: false) {
      if hasProfileDataForDisplay {
    VStack(alignment: .leading, spacing: 0) {
      profileHeader
        .padding(.top, 20)

      FlatSectionHeader(LocalizationSupport.localized("Account Info"))
        .padding(.top, 32)

      FlatCard(padding: 0, outlined: true) {
        VStack(spacing: 0) {
          ForEach($viewModel.contactRows, id: \.description) { $row in
            ProfileInfoRow(parameter: $row, isEditing: viewModel.isEditing)

            if row.description != viewModel.contactRows.last?.description {
              FlatRule()
            }
          }
        }
      }
      .padding(.top, 14)

      if viewModel.shouldShowTeachingDetails {
        FlatSectionHeader(LocalizationSupport.localized("Teaching Details"))
          .padding(.top, 32)

        teachingCard(
          title: LocalizationSupport.localized("Grade Levels Taught"),
          chips: viewModel.gradeLevels,
          includeAdd: viewModel.gradeLevels.isEmpty,
          editAction: showProfileEditor,
          addAction: showProfileEditor
        )
        .padding(.top, 14)

        teachingCard(
          title: LocalizationSupport.localized("Subjects"),
          chips: viewModel.subjectsOrPlaceholder,
          includeAdd: viewModel.subjects.isEmpty,
          editAction: { isShowingSubjectEditor = true },
          addAction: { isShowingSubjectEditor = true }
        )
        .padding(.top, 12)

        documentsButton
          .padding(.top, 12)
      }

      FlatSectionHeader(LocalizationSupport.localized("Device Permissions"))
        .padding(.top, 32)

      FlatCard(padding: 0, outlined: true) {
        VStack(spacing: 0) {
          ProfilePermissionRow(
            icon: "mic.fill",
            title: LocalizationSupport.localized("Microphone"),
            state: viewModel.microphoneState,
            iconColor: permissionColor(viewModel.microphoneState),
            action: viewModel.requestMicrophonePermission
          )

          FlatRule()

          ProfilePermissionRow(
            icon: "camera.fill",
            title: LocalizationSupport.localized("Camera"),
            state: viewModel.cameraState,
            iconColor: permissionColor(viewModel.cameraState),
            action: viewModel.requestCameraPermission
          )

          FlatRule()

          ProfilePermissionRow(
            icon: "bell.fill",
            title: LocalizationSupport.localized("Notifications"),
            state: viewModel.notificationsState,
            iconColor: permissionColor(viewModel.notificationsState),
            action: viewModel.manageNotifications
          )
        }
      }
      .padding(.top, 14)
    }
    .padding(.horizontal, 20)
    .padding(.bottom, 40)
      } else {
        profileLoadingView
      }
	}
    .background(theme.flatSurface)
			.task {
              await loadProfileForDisplay()
			}
            .sheet(isPresented: $isShowingProfileEditor, onDismiss: {
              viewModel.cancelProfileEditing()
            }) {
              NavigationStack {
                ProfileEditView(viewModel: viewModel)
              }
              .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
              .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
              .id(languagePreference)
            }
            .sheet(isPresented: $isShowingSubjectEditor, onDismiss: {
              Task { await viewModel.loadProfile() }
            }) {
              NavigationStack {
                TeacherSubjectsView(isEditing: true)
              }
              .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
              .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
              .id(languagePreference)
            }
            .sheet(isPresented: $isShowingDocuments, onDismiss: {
              // Refresh the "Complete Your Documents" prompt after the teacher
              // may have uploaded a missing document (bug #24).
              Task { await viewModel.loadProfile() }
            }) {
              NavigationStack {
                TeacherDocumentsView()
              }
              .environment(\.locale, LocalizationSupport.locale(languagePreference: languagePreference))
              .environment(\.layoutDirection, LocalizationSupport.layoutDirection(languagePreference: languagePreference))
              .id(languagePreference)
            }
	  }
	  
  var profileLoadingView: some View {
    VStack(spacing: 12) {
      if let error = viewModel.errorMessage {
        Text(error)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(theme.flatCritical)

        Button {
          Task { await loadProfileForDisplay() }
        } label: {
          Text(LocalizationSupport.localized("Retry"))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.flatInk)
        }
        .buttonStyle(.plain)
      } else {
        ProgressView()
          .tint(theme.flatInk)

        Text(LocalizationSupport.localized("Loading profile..."))
          .font(.system(size: 14))
          .foregroundStyle(theme.flatInkMuted)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 420)
    .padding(.horizontal, 20)
  }

	  // Name leads at page-title scale with the photo trailing it, matching the
	  // account screen in the reference.
	  var profileHeader: some View {
	VStack(alignment: .leading, spacing: 0) {
	  HStack(alignment: .top, spacing: 16) {
		VStack(alignment: .leading, spacing: 8) {
		  Text(viewModel.name)
			.font(.system(size: 34, weight: .bold))
			.foregroundStyle(theme.flatInk)
			.lineLimit(2)
			.minimumScaleFactor(0.7)

		  FlatChip(title: viewModel.role)

		  // Teacher verification badge is intentionally hidden for now.
		}

		Spacer()

		ZStack(alignment: .bottomTrailing) {
		  profilePhotoButton
		}
	  }

	  Text(viewModel.memberSince)
		.font(.system(size: 14))
		.foregroundStyle(theme.flatInkMuted)
		.padding(.top, 12)

	  Button {
		showProfileEditor()
	  } label: {
		FlatChip(title: LocalizationSupport.localized("Edit Profile"), systemImage: "pencil")
	  }
	  .buttonStyle(.plain)
	  .padding(.top, 14)
	}
	.frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder
  var profilePhotoButton: some View {
#if !os(Android)
    PhotoSourceButton(onImageData: { data in
      viewModel.uploadProfileImage(data: data)
    }) {
      profilePhotoContent
    }
#else
    Button {
      showAndroidPhotoSourceDialog = true
    } label: {
      profilePhotoContent
    }
    .buttonStyle(.plain)
    .confirmationDialog(
      LocalizationSupport.localized("Add a photo"),
      isPresented: $showAndroidPhotoSourceDialog,
      titleVisibility: .visible
    ) {
      Button(LocalizationSupport.localized("Take Photo")) {
        pickAndroidProfilePhoto(source: .camera)
      }
      Button(LocalizationSupport.localized("Choose from Library")) {
        pickAndroidProfilePhoto(source: .gallery)
      }
      Button(LocalizationSupport.localized("Cancel"), role: .cancel) {}
    }
#endif
  }

  var profilePhotoContent: some View {
    ZStack(alignment: .bottomTrailing) {
      Group {
        ProfileAvatarView(
          imageURL: viewModel.profileImageURL,
          size: 88,
          fallbackSystemImage: "person.crop.circle.fill",
          background: theme.flatSurfaceRaised,
          tint: theme.flatInk
        )
      }
      .frame(width: 88, height: 88)
      .clipShape(Circle())

      Circle()
        .fill(theme.flatInk)
        .frame(width: 30, height: 30)
        .overlay {
          if viewModel.isUploadingPhoto {
            ProgressView()
              .scaleEffect(0.7)
              .tint(theme.flatInkInverse)
          } else {
            PlatformIcon(
              systemName: "camera.fill",
              size: 12,
              weight: .bold,
              color: theme.flatInkInverse
            )
          }
        }
    }
  }

  var defaultProfileIcon: some View {
    Circle()
      .fill(theme.appPurpleSoft)
      .overlay {
        PlatformIcon(
          systemName: "person.crop.circle.fill",
          size: 72,
          color: theme.appPurple
        )
      }
  }
  
  func permissionColor(_ state: PermissionState) -> Color {
	switch state {
	case .granted: return theme.flatPositive
	case .denied: return theme.flatCritical
	case .notDetermined: return theme.flatInkMuted
	}
  }

  private func showProfileEditor() {
    viewModel.editProfile()
    isShowingProfileEditor = true
  }

  private func loadProfileForDisplay() async {
    if viewModel.hasDisplayableProfileData {
      hasProfileDataForDisplay = true
      return
    }

    hasProfileDataForDisplay = false
    var didStartLoad = false
    while !Task.isCancelled {
      if viewModel.hasDisplayableProfileData {
        hasProfileDataForDisplay = true
        return
      }

      if !didStartLoad || !viewModel.isLoading {
        didStartLoad = true
        Task { await viewModel.loadProfile() }
      }

      try? await Task.sleep(for: .seconds(1))
    }
  }

  var documentsButton: some View {
	Button {
	  isShowingDocuments = true
	} label: {
	  FlatCard {
		HStack(spacing: 14) {
		  FlatIconTile(systemName: viewModel.hasMissingDocuments ? "doc.badge.plus" : "doc.text.fill", size: 44, background: theme.flatSurface)

		  VStack(alignment: .leading, spacing: 3) {
			Text(viewModel.hasMissingDocuments
				 ? LocalizationSupport.localized("Complete Your Documents")
				 : LocalizationSupport.localized("Documents Uploaded"))
			  .font(.system(size: 15, weight: .bold))
			  .foregroundStyle(theme.flatInk)

			Text(viewModel.hasMissingDocuments
				 ? LocalizationSupport.localized("Upload your remaining verification documents")
				 : LocalizationSupport.localized("View the verification documents you uploaded"))
			  .font(.system(size: 13))
			  .foregroundStyle(theme.flatInkMuted)
		  }

		  Spacer()

		  PlatformIcon(systemName: "chevron.right", size: 13, weight: .medium, color: theme.flatInkMuted)
		}
	  }
	}
	.buttonStyle(.plain)
  }

  func teachingCard(
	title: String,
	chips: [String],
	includeAdd: Bool,
	editAction: @escaping () -> Void,
	addAction: @escaping () -> Void
  ) -> some View {
	FlatCard {
	  VStack(alignment: .leading, spacing: 14) {
		HStack {
		  Text(title)
			.font(.system(size: 13))
			.foregroundStyle(theme.flatInkMuted)

		  Spacer()

		  Button(action: editAction) {
			Text(LocalizationSupport.localized("Edit"))
			  .font(.system(size: 14, weight: .bold))
			  .foregroundStyle(theme.flatInk)
		  }
		  .buttonStyle(.plain)
		}

		ChipGrid(minimumItemWidth: 96, spacing: 8) {
		  ForEach(chips, id: \.self) { chip in
			FlatChip(title: chip, outlined: true)
		  }

		  if includeAdd {
			Button(action: addAction) {
			  FlatChip(title: LocalizationSupport.localized("+ Add"), outlined: true)
			}
			.buttonStyle(.plain)
		  }
		}
	  }
	  }
  }

#if os(Android)
  enum AndroidPhotoSource {
    case camera
    case gallery
  }

  private func pickAndroidProfilePhoto(source: AndroidPhotoSource) {
    Task {
      do {
        if source == .camera {
          let cameraState = await PermissionService.shared.requestCapturePermission(for: .camera)
          guard cameraState.isGranted else {
            viewModel.errorMessage = LocalizationSupport.localized("Camera access is required to take a photo.")
            return
          }
        }
        let base64 = try await Task.detached(priority: .userInitiated) {
          switch source {
          case .camera:  return try AndroidProfileImagePickerBridge.captureImageBase64()
          case .gallery: return try AndroidProfileImagePickerBridge.pickImageBase64()
          }
        }.value
        guard !base64.isEmpty, let data = Data(base64Encoded: base64) else { return }
        viewModel.uploadProfileImage(data: data)
      } catch {
        viewModel.errorMessage = error.localizedDescription
      }
    }
  }
#endif
}

struct ProfileEditView: View {
  @State var viewModel: ProfileViewModel
  @Environment(\.dismiss) var dismiss
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.layoutDirection) var layoutDirection
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }
  var contentAlignment: HorizontalAlignment {
    layoutDirection == .rightToLeft ? .trailing : .leading
  }

  var body: some View {
    ScrollView(.vertical, showsIndicators: false) {
	  VStack(alignment: .leading, spacing: 0) {
        Text(LocalizationSupport.localized("Edit Profile"))
          .font(.system(size: 26, weight: .bold))
          .foregroundStyle(theme.authPrimaryText)
          .padding(.top, 24)

        Text(LocalizationSupport.localized("Update the details students and teachers use to recognize and contact you."))
          .font(.system(size: 13))
          .foregroundStyle(theme.authSecondaryText)
          .lineSpacing(5)
          .multilineTextAlignment(.leading)
          .padding(.top, 8)

        VStack(spacing: 16) {
          ForEach($viewModel.contactRows, id: \.description) { $row in
            if viewModel.roleType == .student && row.description == LocalizationSupport.localized("Grade") {
              ProfileGradePicker(
                title: row.description,
                selectedGrade: $row.value,
                grades: viewModel.availableStudentGrades
              )
            } else if viewModel.roleType == .student && row.description == LocalizationSupport.localized("Date of Birth") {
              ProfileDateOfBirthPicker(
                title: row.description,
                date: $viewModel.dateOfBirth
              )
            } else {
              ProfileEditInfoRow(parameter: $row)
            }
          }

          if viewModel.roleType == .teacher {
            ProfileTeachingGradePicker(
              title: LocalizationSupport.localized("Grade Levels Taught"),
              selectedGrades: $viewModel.selectedTeachingGrades
            )
          }
        }
        .padding(.top, 28)

        if let error = viewModel.errorMessage {
          Text(error)
            .font(.system(size: 12))
            .foregroundStyle(.red)
            .padding(.top, 16)
        }

        AuthPrimaryButton(
          title: viewModel.isLoading ? LocalizationSupport.localized("Saving...") : LocalizationSupport.localized("Save Changes"),
          systemImage: "checkmark",
          isEnabled: !viewModel.isLoading
        ) {
          Task { @MainActor in
            viewModel.saveProfileEdits()
          }
        }
        .padding(.top, 28)
        .padding(.bottom, 24)
      }
      .padding(.horizontal, 18)
    }
    .background(Color(.systemBackground))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) {
        Button(LocalizationSupport.localized("Cancel")) {
          viewModel.cancelProfileEditing()
          dismiss()
        }
      }
    }
    .onChange(of: viewModel.isEditing) { _, isEditing in
      if !isEditing {
        dismiss()
      }
    }
  }
}

struct ProfileTeachingGradePicker: View {
  let title: String
  @Binding var selectedGrades: Set<String>
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.layoutDirection) var layoutDirection
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }
  var contentAlignment: HorizontalAlignment {
    layoutDirection == .rightToLeft ? .trailing : .leading
  }

  let grades = ProfileViewModel.availableTeachingGrades

  var body: some View {
    VStack(alignment: contentAlignment, spacing: 10) {
      HStack {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.authPrimaryText)

        Spacer()

        Text(selectedGrades.isEmpty ? LocalizationSupport.localized("Choose grades") : String(format: LocalizationSupport.localized("%d selected"), selectedGrades.count))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(theme.authSecondaryText)
          .padding(.horizontal, 10)
          .frame(height: 24)
          .background(theme.authFieldBorder.opacity(0.7))
          .clipShape(Capsule())
      }
	  HStack {
		Spacer()
		FlowLayout(spacing: 10) {
		  ForEach(grades, id: \.self) { grade in
			ProfileTeachingGradeChip(
			  title: grade,
			  isSelected: selectedGrades.contains(grade)
			) {
			  toggleGrade(grade)
			}
		  }
		}
		Spacer()
	  }
    }
  }

  private func toggleGrade(_ grade: String) {
    if selectedGrades.contains(grade) {
      selectedGrades.remove(grade)
    } else {
      selectedGrades.insert(grade)
    }
  }
}

struct ProfileDateOfBirthPicker: View {
  let title: String
  @Binding var date: Date?
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  /// Sensible default when the student first sets a date of birth.
  private var defaultDate: Date {
    Calendar.current.date(byAdding: .year, value: -12, to: Date()) ?? Date()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(theme.authPrimaryText)

      if let currentDate = date {
        HStack {
          DatePicker(
            "",
            selection: Binding(get: { currentDate }, set: { date = $0 }),
            in: Date.distantPast...Date(),
            displayedComponents: .date
          )
          .labelsHidden()
#if !os(Android)
          .datePickerStyle(.compact)
#endif

          Spacer()

          Button {
            date = nil
          } label: {
            Text(LocalizationSupport.localized("Clear"))
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(theme.appPink)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(theme.authFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(theme.authFieldBorder, lineWidth: 1)
        }
      } else {
        Button {
          date = defaultDate
        } label: {
          HStack {
            Text(LocalizationSupport.localized("Set date of birth"))
              .font(.system(size: 17))
              .foregroundStyle(theme.authSecondaryText)

            Spacer()

            PlatformIcon(
              systemName: "calendar",
              size: 14,
              weight: .semibold,
              color: theme.authIcon
            )
          }
          .padding(.horizontal, 16)
          .frame(height: 56)
          .background(theme.authFieldBackground)
          .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
              .stroke(theme.authFieldBorder, lineWidth: 1)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }
}

struct ProfileGradePicker: View {
  let title: String
  @Binding var selectedGrade: String
  let grades: [String]
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(title)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(theme.authPrimaryText)

      Menu {
        ForEach(grades, id: \.self) { grade in
          Button(grade) {
            selectedGrade = grade
          }
        }
      } label: {
        HStack {
          Text(selectedGrade.isEmpty ? LocalizationSupport.localized("Select") : selectedGrade)
            .font(.system(size: 17))
            .foregroundStyle(selectedGrade.isEmpty ? theme.authSecondaryText : theme.authPrimaryText)

          Spacer()

          PlatformIcon(
            systemName: "chevron.down",
            size: 12,
            weight: .semibold,
            color: theme.authIcon
          )
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(theme.authFieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(theme.authFieldBorder, lineWidth: 1)
        }
      }
    }
  }
}

struct ProfileCurrencyPicker: View {
  let title: String
  @Binding var selectedCurrency: String
  var availableCurrencies:[String]
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.layoutDirection) var layoutDirection
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }
  var contentAlignment: HorizontalAlignment {
    layoutDirection == .rightToLeft ? .trailing : .leading
  }


  var body: some View {
    VStack(alignment: contentAlignment, spacing: 10) {
      HStack {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.authPrimaryText)

        Spacer()

        Text(selectedCurrency)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(theme.authSecondaryText)
          .padding(.horizontal, 10)
          .frame(height: 24)
          .background(theme.authFieldBorder.opacity(0.7))
          .clipShape(Capsule())
      }
      HStack {
        Spacer()
        FlowLayout(spacing: 10) {
          ForEach(availableCurrencies, id: \.self) { code in
            ProfileCurrencyChip(
              title: code,
              isSelected: selectedCurrency == code
            ) {
              selectedCurrency = code
            }
          }
        }
        Spacer()
      }
    }
  }
}

struct ProfileCurrencyChip: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(theme.authPrimaryText)
        .padding(.horizontal, 18)
        .frame(height: 34)
        .background(isSelected ? theme.authPink : theme.authPinkSoft)
        .clipShape(Capsule())
        .overlay {
          Capsule()
            .stroke(isSelected ? theme.authPink : theme.authFieldBorder, lineWidth: 1)
        }
    }
    .buttonStyle(.plain)
  }
}

struct ProfileTeachingGradeChip: View {
  let title: String
  let isSelected: Bool
  let action: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button(action: action) {
      HStack(spacing: 7) {
        PlatformIcon(systemName: "graduationcap")
          .font(.system(size: 12, weight: .semibold))

        Text(LocalizationSupport.localized(title))
          .font(.system(size: 13, weight: .medium))
      }
      .foregroundStyle(theme.authPrimaryText)
      .padding(.horizontal, 14)
      .frame(height: 34)
      .background(isSelected ? theme.authPink : theme.authPinkSoft)
      .clipShape(Capsule())
      .overlay {
        Capsule()
          .stroke(isSelected ? theme.authPink : theme.authFieldBorder, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }
}

struct ProfileEditInfoRow: View {
  @Binding var parameter: Parameter

  var body: some View {
    AuthInputField(
      title: parameter.description,
      placeholder: parameter.description,
      systemImage: parameter.image,
      text: $parameter.value,
      keyboardType: keyboardType,
      textContentType: textContentType
    )
  }

  private var keyboardType: UIKeyboardType {
    switch parameter.description {
    case LocalizationSupport.localized("Email"):
      return .emailAddress
    case LocalizationSupport.localized("Phone"):
      return .phonePad
    default:
      return .default
    }
  }

  private var textContentType: UITextContentType? {
    switch parameter.description {
    case LocalizationSupport.localized("Full Name"):
      return .name
    case LocalizationSupport.localized("Email"):
      return .emailAddress
    case LocalizationSupport.localized("Phone"):
      return .telephoneNumber
    default:
      return nil
    }
  }
}

#if os(Android)
private enum AndroidProfileImagePickerBridge {
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

struct ProfilePermissionRow: View {
  let icon: String
  let title: String
  let state: PermissionState
  let iconColor: Color
  let action: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	HStack(spacing: 14) {
	  FlatIconTile(systemName: icon, size: 44, tint: iconColor)

	  VStack(alignment: .leading, spacing: 3) {
		Text(title)
		  .font(.system(size: 15, weight: .bold))
		  .foregroundStyle(theme.flatInk)

		Text(state.subtitle)
		  .font(.system(size: 13))
		  .foregroundStyle(iconColor)
	  }

	  Spacer()

	  Button(action: action) {
		Text(state.actionTitle)
		  .font(.system(size: 14, weight: .bold))
		  .foregroundStyle(theme.flatInk)
	  }
	  .buttonStyle(.plain)
	}
	.padding(.horizontal, 16)
	.padding(.vertical, 14)
  }
}

struct ProfileInfoRow: View {
  @Binding var parameter: Parameter
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  let isEditing: Bool
  var body: some View {
	HStack(spacing: 14) {
	  FlatIconTile(systemName: parameter.image, size: 44)

	  VStack(alignment: .leading, spacing: 3) {
		Text(parameter.description)
		  .font(.system(size: 13))
		  .foregroundStyle(theme.flatInkMuted)

		if isEditing {
		  TextField(parameter.description, text: $parameter.value)
			.font(.system(size: 16, weight: .bold))
			.foregroundStyle(theme.flatInk)
			.lineLimit(1)
			.minimumScaleFactor(0.75)
			.multilineTextAlignment(.leading)
			.environment(\.layoutDirection, .leftToRight)
		} else {
		  Text(parameter.value.isEmpty ? "-" : parameter.value)
			.font(.system(size: 16, weight: .bold))
			.foregroundStyle(theme.flatInk)
			.lineLimit(1)
			.minimumScaleFactor(0.75)
			.frame(maxWidth: .infinity, alignment: .leading)
			.multilineTextAlignment(.leading)
		}
	  }

	  Spacer()
	}
	.padding(.horizontal, 16)
	.padding(.vertical, 14)
  }
}
