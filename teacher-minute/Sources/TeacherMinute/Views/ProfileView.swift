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
  @State var hasProfileDataForDisplay = false
  @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
#if !os(Android)
  @State private var profilePhotoItem: PhotosPickerItem?
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
		HStack {
		  Text(LocalizationSupport.localized("Profile"))
			.font(.system(size: 24, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
		  
		  Spacer()
		  
		  Button {
		    showProfileEditor()
		  } label: {
			Circle()
			  .fill(theme.appPrimaryText)
			  .frame(width: 42, height: 42)
			  .shadow(color: theme.appPrimaryText.opacity(0.05), radius: 12, x: 0, y: 6)
		      .overlay {
					PlatformIcon(systemName: "pencil", color: theme.appGreen)
					  .font(.system(size: 15, weight: .bold))
		      }
		  }
		  .buttonStyle(.plain)
		}
		.padding(.top, 24)
		
		profileHeader
		  .padding(.top, 26)
		
		Text(LocalizationSupport.localized("Account Info"))
		  .font(.system(size: 16, weight: .bold))
		  .foregroundStyle(theme.appPrimaryText)
		  .padding(.top, 30)
		
		VStack(spacing: 14) {
		  ForEach($viewModel.contactRows, id: \.description) { $row in
			ProfileInfoRow(parameter: $row,
						   isEditing: viewModel.isEditing)
		  }
		}
		.padding(.top, 14)
		
		if viewModel.shouldShowTeachingDetails {
		  Text(LocalizationSupport.localized("Teaching Details"))
			.font(.system(size: 16, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
			.padding(.top, 30)
		  
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
			  .padding(.top, 18)
			}
		
		Text(LocalizationSupport.localized("Device Permissions"))
		  .font(.system(size: 16, weight: .bold))
		  .foregroundStyle(theme.appPrimaryText)
		  .padding(.top, 30)
		
			VStack(spacing: 14) {
			  ProfilePermissionRow(
				icon: "mic.fill",
				title: LocalizationSupport.localized("Microphone"),
				state: viewModel.microphoneState,
				iconColor: permissionColor(viewModel.microphoneState),
                action: viewModel.requestMicrophonePermission
              )

			  ProfilePermissionRow(
				icon: "camera.fill",
				title: LocalizationSupport.localized("Camera"),
				state: viewModel.cameraState,
				iconColor: permissionColor(viewModel.cameraState),
                action: viewModel.requestCameraPermission
              )

			  ProfilePermissionRow(
				icon: "bell.fill",
				title: LocalizationSupport.localized("Notifications"),
				state: viewModel.notificationsState,
				iconColor: permissionColor(viewModel.notificationsState),
                action: viewModel.manageNotifications
              )
			}
	  }
	  .padding(.horizontal, 18)
	  .padding(.bottom, 24)
      } else {
        profileLoadingView
      }
	}
		.background(Color(.systemBackground))
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
#if !os(Android)
        .onChange(of: profilePhotoItem) { _, item in
          loadProfilePhoto(item)
        }
#endif
	  }
	  
  var profileLoadingView: some View {
    VStack(spacing: 12) {
      if let error = viewModel.errorMessage {
        Text(error)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.red)

        Button {
          Task { await loadProfileForDisplay() }
        } label: {
          Text(LocalizationSupport.localized("Retry"))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.appPink)
        }
        .buttonStyle(.plain)
      } else {
        ProgressView()
          .tint(theme.appPink)

        Text(LocalizationSupport.localized("Loading profile..."))
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.appSecondaryText)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 420)
    .padding(.horizontal, 18)
  }

	  var profileHeader: some View {
	VStack(spacing: 0) {
		  ZStack(alignment: .bottomTrailing) {
            profilePhotoButton
		  }
	  
	  Text(viewModel.name)
		.font(.system(size: 22, weight: .bold))
		.foregroundStyle(theme.appPrimaryText)
		.padding(.top, 14)
	  
	  HStack(spacing: 8) {
		SmallPill(title: viewModel.role, foreground: theme.appPurple, background: theme.appPurpleSoft)
		
		if viewModel.roleType == .teacher {
		  SmallPill(
		    title: LocalizationSupport.localized(viewModel.isVerified ? "Verified" : "Not Verified"),
		    foreground: viewModel.isVerified ? theme.appGreen : theme.red,
		    background: viewModel.isVerified ? theme.appGreenSoft : theme.red.opacity(0.12)
		  )
		}
	  }
	  .padding(.top, 8)
	  
	  Text(viewModel.memberSince)
		.font(.system(size: 13))
		.foregroundStyle(theme.appSecondaryText)
		.padding(.top, 12)
	}
	.frame(maxWidth: .infinity)
  }

  @ViewBuilder
  var profilePhotoButton: some View {
#if !os(Android)
    PhotosPicker(selection: $profilePhotoItem, matching: .images) {
      profilePhotoContent
    }
    .buttonStyle(.plain)
#else
    Button {
      pickAndroidProfilePhoto()
    } label: {
      profilePhotoContent
    }
    .buttonStyle(.plain)
#endif
  }

  var profilePhotoContent: some View {
    ZStack(alignment: .bottomTrailing) {
      Group {
        ProfileAvatarView(
          imageURL: viewModel.profileImageURL,
          size: 96,
          fallbackSystemImage: "person.crop.circle.fill",
          background: theme.appPurpleSoft,
          tint: theme.appPurple
        )
      }
      .frame(width: 96, height: 96)
      .clipShape(Circle())

      Circle()
        .fill(theme.appPink)
        .frame(width: 30, height: 30)
        .overlay {
          if viewModel.isUploadingPhoto {
            ProgressView()
              .scaleEffect(0.7)
              .tint(theme.appPrimaryText)
          } else {
            PlatformIcon(
              systemName: "camera.fill",
              size: 12,
              weight: .bold,
              color: theme.appPrimaryText
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
	case .granted: return theme.appGreen
	case .denied: return theme.red
	case .notDetermined: return theme.appSecondaryText
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

  func teachingCard(
	title: String,
	chips: [String],
	includeAdd: Bool,
	editAction: @escaping () -> Void,
	addAction: @escaping () -> Void
  ) -> some View {
	RoundedInfoCard {
	  VStack(alignment: .leading, spacing: 16) {
		HStack {
		  Text(title)
			.font(.system(size: 12))
			.foregroundStyle(theme.appSecondaryText)
		  
		  Spacer()
		  
		  Button(action: editAction) {
			Text(LocalizationSupport.localized("Edit"))
			  .font(.system(size: 12, weight: .medium))
			  .foregroundStyle(theme.appPink)
		  }
		  .buttonStyle(.plain)
		}
		
		ChipGrid(minimumItemWidth: 96, spacing: 8) {
		  ForEach(chips, id: \.self) { chip in
			SmallPill(title: chip, foreground: theme.appPink, background: theme.appPinkSoft)
		  }
		  
		  if includeAdd {
			Button(action: addAction) {
			  Text(LocalizationSupport.localized("+ Add"))
				.font(.system(size: 12, weight: .medium))
				.foregroundStyle(theme.appSecondaryText)
				.padding(.horizontal, 12)
				.frame(height: 28)
				.background(theme.appGrayBackground)
				.clipShape(Capsule())
			}
			.buttonStyle(.plain)
		  }
		}
	  }
	  }
  }

#if !os(Android)
  private func loadProfilePhoto(_ item: PhotosPickerItem?) {
    guard let item else { return }
    Task {
      if let data = try? await item.loadTransferable(type: Data.self) {
        viewModel.uploadProfileImage(data: data)
      }
    }
  }
#else
  private func pickAndroidProfilePhoto() {
    Task {
      do {
        let base64 = try await Task.detached(priority: .userInitiated) {
          try AndroidProfileImagePickerBridge.pickImageBase64()
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
            ProfileEditInfoRow(parameter: $row)
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
        Button("Cancel") {
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

        Text(LocalizedStringKey(title))
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

  static func pickImageBase64() throws -> String {
    try jniContext {
      try managerClass.callStatic(
        method: pickImageBase64Method,
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
	RoundedInfoCard {
	  HStack(spacing: 14) {
		Circle()
		  .fill(iconColor.opacity(0.12))
		  .frame(width: 42, height: 42)
		  .overlay {
			PlatformIcon(systemName: icon)
			  .font(.system(size: 16, weight: .semibold))
			  .foregroundStyle(iconColor)
		  }
		
		VStack(alignment: .leading, spacing: 4) {
		  Text(title)
			.font(.system(size: 14, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
		  
		  Text(state.subtitle)
			.font(.system(size: 12, weight: .semibold))
			.foregroundStyle(iconColor)
		}
		
		Spacer()
		
        Button(action: action) {
          Text(state.actionTitle)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.appPink)
        }
        .buttonStyle(.plain)
	  }
	}
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
	RoundedInfoCard {
	  HStack(spacing: 14) {
		Circle()
		  .fill(theme.appPurpleSoft)
		  .frame(width: 42, height: 42)
		  .overlay {
			PlatformIcon(systemName: parameter.image)
			  .font(.system(size: 17, weight: .semibold))
			  .foregroundStyle(theme.appPurple)
		  }
		
		VStack(alignment: .leading, spacing: 4) {
		  Text(parameter.description)
			.font(.system(size: 14))
			.foregroundStyle(theme.appPrimaryText)
		  
		  if isEditing {
		    TextField(parameter.description, text: $parameter.value)
		      .font(.system(size: 16, weight: .bold))
		      .foregroundStyle(theme.appPrimaryText)
		      .lineLimit(1)
		      .minimumScaleFactor(0.75)
		      .multilineTextAlignment(.leading)
		      .environment(\.layoutDirection, .leftToRight)
		  } else {
		    Text(parameter.value.isEmpty ? "-" : parameter.value)
		      .font(.system(size: 16, weight: .bold))
		      .foregroundStyle(theme.appPrimaryText)
		      .lineLimit(1)
		      .minimumScaleFactor(0.75)
		      .frame(maxWidth: .infinity, alignment: .trailing)
		      .multilineTextAlignment(.trailing)
		  }
		}
		
		Spacer()
	  }
	}
  }
}
