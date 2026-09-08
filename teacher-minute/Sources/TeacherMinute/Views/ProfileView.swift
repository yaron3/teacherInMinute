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
  /// `@Bindable`, not `@State`. MainTabView already owns this view model in its
  /// own `@State` and passes it down; wrapping it a second time here left the
  /// body reading a copy that Skip never re-read, so a completed load updated
  /// the view model — the logs showed name and contact rows arriving — while
  /// the screen kept rendering its initial placeholders. `@Bindable` observes
  /// without taking ownership, and still vends the `$viewModel` bindings the
  /// editor sheets need.
  @Bindable var viewModel: ProfileViewModel
  @State var isShowingProfileEditor = false
  @State var isShowingSubjectEditor = false
  @State var isShowingDocuments = false
  @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
#if os(Android)
  @State var showAndroidPhotoSourceDialog = false
#endif
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  init(viewModel: ProfileViewModel = ProfileViewModel()) {
	self.viewModel = viewModel
  }
  var body: some View {
	ScrollView(.vertical, showsIndicators: false) {
      // The profile renders straight away and fills in as the load lands, the
      // way the home tabs do. Swapping the whole subtree on a loaded flag did
      // not survive Skip: the load completed in tens of milliseconds and set
      // `isProfileLoaded`, but the branch never re-evaluated on Android and the
      // screen sat on "Loading profile..." indefinitely. Rendering one tree and
      // letting the individual fields update removes the branch entirely.
    VStack(alignment: .leading, spacing: 0) {
      if let error = viewModel.errorMessage {
        profileLoadError(error)
      }
      FlatCard(padding: 0, outlined: true) {
        VStack(spacing: 0) {
          profileHeader
            .padding(16)

          FlatRule()

          ProfileInfoRow(
            parameter: .constant(Parameter(
              description: LocalizationSupport.localized("Email"),
              value: viewModel.email,
              image: "envelope.fill"
            )),
            isEditing: false,
          )
          FlatRule()
          ProfileInfoRow(
            parameter: .constant(Parameter(
              description: LocalizationSupport.localized("Phone"),
              value: viewModel.phoneNumber,
              image: "phone.fill"
            )),
            isEditing: false
          )
          FlatRule()
//          ProfileInfoRow(
//            parameter: .constant(Parameter(
//              description: LocalizationSupport.localized("Username"),
//              value: viewModel.username,
//              image: "person.text.rectangle.fill"
//            )),
//            isEditing: false
//          )
        }
      }
      .padding(.top, 20)
	  if viewModel.shouldShowTeacherPaymentsMethod {
		FlatSectionHeader("")
		  .padding(.top, 32)
		FlatCard {
		  VStack {
			HStack {
			  Label(LocalizationSupport.localized("Payment Method"), systemImage: "creditcard")
			  Spacer()
			  Button(action: showProfileEditor) {
				Text(LocalizationSupport.localized("Edit"))
				  .font(.system(size: 14, weight: .bold))
				  .foregroundStyle(theme.primaryText)
			  }
			  .buttonStyle(.plain)
			}
			.padding(6)
			
			HStack {
			  PlatformIcon(systemName: viewModel.payoutMethodSystemImage)
			  VStack(alignment: .leading, spacing: 4) {
				Text(viewModel.payoutMethodTitle)
				  .font(.system(size: 14, weight: .bold))
				  .foregroundStyle(theme.primaryText)
				Text(viewModel.payoutMethodDetail)
				  .font(.system(size: 13))
				  .foregroundStyle(viewModel.hasPayoutMethod ? theme.primaryText : theme.secondaryText)
			  }
			  Spacer()
			}
		  }
		}
//		teachingCard(
//		  title: LocalizationSupport.localized("Active accounts"),
//		  chips: viewModel.paymentsMethdsLabels,
//		  includeAdd: viewModel.paymentsMethdsLabels.isEmpty,
//		  editAction: showProfileEditor,
//		  addAction: showProfileEditor
//		)

	  }
      // Teacher payouts only for now; the student's saved-for-charging PayPal
      // comes later and needs a vaulted account rather than an address.
      if viewModel.shouldShowTeacherPaymentsMethod {
        savedPayPalSection
          .padding(.top, 32)
      }
      if viewModel.shouldShowTeachingDetails {
        FlatSectionHeader(LocalizationSupport.localized("Teaching Details"))
          .padding(.top, 32)

        teachingCard(
          title: LocalizationSupport.localized("Grade Levels Taught"),
          chips: viewModel.gradeLevelLabels,
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
	}
    .background(theme.screenBackground)
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
	  
  /// Shown above the profile when a load failed, rather than in place of it.
  /// A failure leaves the fields at their placeholder values, which is still a
  /// usable screen — the tab bar and the retry stay reachable either way.
  func profileLoadError(_ error: String) -> some View {
    VStack(spacing: 12) {
      Text(error)
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(theme.danger)

      Button {
        Task { await viewModel.loadProfile() }
      } label: {
        Text(LocalizationSupport.localized("Retry"))
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(theme.primaryText)
      }
      .buttonStyle(.plain)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 16)
  }

	  var profileHeader: some View {
	HStack(alignment: .center, spacing: 16) {
	  ZStack(alignment: .bottomTrailing) {
		profilePhotoButton
	  }
	  VStack(alignment: .leading, spacing: 6) {
		HStack(alignment: .center, spacing: 6) {
		  Text(viewModel.name)
			.font(.system(size: 22, weight: .bold))
			.foregroundStyle(theme.primaryText)
			.lineLimit(2)
			.minimumScaleFactor(0.7)
		  Spacer()
		  Button(action: showProfileEditor) {
			PlatformIcon(systemName: "pencil", size: 14, weight: .semibold, color: theme.secondaryText)
			  
		  }
		  .buttonStyle(.plain)
		  
		}

		Text(viewModel.role)
		  .font(.system(size: 14))
		  .foregroundStyle(theme.secondaryText)

		if viewModel.hasRating {
		  HStack(spacing: 4) {
			Text(LessonFormatting.ratingText(viewModel.rating))
			  .font(.system(size: 13, weight: .semibold))
			  .foregroundStyle(theme.primaryText)

			RatingStarsView(rating: viewModel.rating, size: 12)

			Text(viewModel.reviewCountText)
			  .font(.system(size: 12))
			  .foregroundStyle(theme.secondaryText)
		  }
		}
	  }

	  


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
          background: theme.accentBackground,
          tint: theme.accentStrong,
          initial: viewModel.nameInitial
        )
      }
      .frame(width: 88, height: 88)
      .clipShape(Circle())

      Circle()
        .fill(theme.accent)
        .frame(width: 30, height: 30)
        .overlay {
          if viewModel.isUploadingPhoto {
            ProgressView()
              .scaleEffect(0.7)
              .tint(theme.onAccentText)
          } else {
            PlatformIcon(
              systemName: "camera.fill",
              size: 12,
              weight: .bold,
              color: theme.onAccentText
            )
          }
        }
    }
  }

  var defaultProfileIcon: some View {
    Circle()
      .fill(theme.accentBackground)
      .overlay {
        PlatformIcon(
          systemName: "person.crop.circle.fill",
          size: 72,
          color: theme.accentStrong
        )
      }
  }
  
  func permissionColor(_ state: PermissionState) -> Color {
	switch state {
	case .granted: return theme.positive
	case .denied: return theme.danger
	case .notDetermined: return theme.secondaryText
	}
  }

  private func showProfileEditor() {
    viewModel.editProfile()
    isShowingProfileEditor = true
  }

  private func loadProfileForDisplay() async {
    guard !viewModel.hasDisplayableProfileData else { return }
    await viewModel.loadProfile()
  }

  var savedPayPalSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      FlatSectionHeader(LocalizationSupport.localized("Saved PayPal")) {
        if viewModel.payPalPayoutEmail == nil, !viewModel.isEditingPayPalEmail {
          Button {
            Task { await viewModel.addPayPalPayoutEmail() }
          } label: {
            if viewModel.isSavingPayPal {
              ProgressView()
            } else {
              FlatChip(title: LocalizationSupport.localized("+ Add"), outlined: true)
            }
          }
          .buttonStyle(.plain)
          .disabled(viewModel.isSavingPayPal)
        }
      }

      FlatCard(outlined: true) {
        if viewModel.isEditingPayPalEmail {
          payPalEmailEditor
        } else if let email = viewModel.payPalPayoutEmail {
          HStack(spacing: 14) {
            FlatIconTile(systemName: "checkmark.circle.fill", tint: theme.positive, background: theme.screenBackground)

            VStack(alignment: .leading, spacing: 3) {
              Text(LocalizationSupport.localized("PayPal"))
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(theme.primaryText)
              Text(email)
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
            }

            Spacer()

            Button {
              viewModel.editPayPalPayoutEmail()
            } label: {
              Text(LocalizationSupport.localized("Change"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.info)
            }
            .buttonStyle(.plain)
          }
        } else {
          Text(LocalizationSupport.localized("No saved PayPal account. Tap \"+ Add\" to save one."))
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
        }
      }

      if let errorMessage = viewModel.payPalVaultErrorMessage {
        Text(errorMessage)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.danger)
      }

      HStack(alignment: .top, spacing: 10) {
        PlatformIcon(systemName: "bolt.fill", size: 16, weight: .bold, color: theme.warning)
        VStack(alignment: .leading, spacing: 4) {
          Text(LocalizationSupport.localized("Where you get paid"))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.warning)
          Text(LocalizationSupport.localized("Your monthly payout is sent to this address, so it must be the email on your PayPal account."))
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.secondaryText)
        }
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(theme.warning.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: flatRadiusSmall, style: .continuous)
          .stroke(theme.warning, lineWidth: 1)
      }
    }
  }

  /// Shown when there is no usable address on the profile yet, or the teacher
  /// asked to change the one there is.
  var payPalEmailEditor: some View {
    VStack(alignment: .leading, spacing: 12) {
      AuthInputField(
        title: LocalizationSupport.localized("PayPal Email"),
        placeholder: LocalizationSupport.localized("name@example.com"),
        systemImage: "envelope",
        text: $viewModel.payPalEmailDraft,
        keyboardType: .emailAddress,
        textContentType: .emailAddress
      )

      HStack(spacing: 12) {
        Button {
          Task { await viewModel.savePayPalPayoutEmail() }
        } label: {
          if viewModel.isSavingPayPal {
            ProgressView()
              .frame(maxWidth: .infinity)
          } else {
            Text(LocalizationSupport.localized("Save Changes"))
              .font(.system(size: 15, weight: .bold))
              .frame(maxWidth: .infinity)
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.isSavingPayPal)

        Button {
          viewModel.cancelPayPalEmailEditing()
        } label: {
          Text(LocalizationSupport.localized("Cancel"))
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.secondaryText)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isSavingPayPal)
      }
    }
  }

  var documentsButton: some View {
	Button {
	  isShowingDocuments = true
	} label: {
	  FlatCard {
		HStack(spacing: 14) {
		  FlatIconTile(systemName: viewModel.hasMissingDocuments ? "doc.badge.plus" : "doc.text.fill", size: 44, background: theme.screenBackground)

		  VStack(alignment: .leading, spacing: 3) {
			Text(viewModel.hasMissingDocuments
				 ? LocalizationSupport.localized("Complete Your Documents")
				 : LocalizationSupport.localized("Documents Uploaded"))
			  .font(.system(size: 15, weight: .bold))
			  .foregroundStyle(theme.primaryText)

			Text(viewModel.hasMissingDocuments
				 ? LocalizationSupport.localized("Upload your remaining verification documents")
				 : LocalizationSupport.localized("View the verification documents you uploaded"))
			  .font(.system(size: 13))
			  .foregroundStyle(theme.secondaryText)
		  }

		  Spacer()

		  PlatformIcon(systemName: "chevron.right", size: 13, weight: .medium, color: theme.secondaryText)
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
			.foregroundStyle(theme.secondaryText)

		  Spacer()

		  Button(action: editAction) {
			Text(LocalizationSupport.localized("Edit"))
			  .font(.system(size: 14, weight: .bold))
			  .foregroundStyle(theme.primaryText)
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
          .foregroundStyle(theme.primaryText)
          .padding(.top, 24)

        Text(LocalizationSupport.localized("Update the details students and teachers use to recognize and contact you."))
          .font(.system(size: 13))
          .foregroundStyle(theme.secondaryText)
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
              ProfileEditInfoRow(
                parameter: $row,
                isValid: viewModel.isRowValid(row),
                errorMessage: viewModel.rowErrorMessage(for: row),
				
              )
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
          isEnabled: viewModel.canSaveProfileEdits
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
	VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.primaryText)

        Spacer()

        Text(selectedGrades.isEmpty ? LocalizationSupport.localized("Choose grades") : String(format: LocalizationSupport.localized("%d selected"), selectedGrades.count))
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(theme.secondaryText)
          .padding(.horizontal, 10)
          .frame(height: 24)
          .background(theme.controlBorder.opacity(0.7))
          .clipShape(Capsule())
      }
	  HStack {
		Spacer()
		FlowLayout(spacing: 10) {
		  ForEach(grades, id: \.self) { grade in
			ProfileTeachingGradeChip(
			  title: LocalizationSupport.localizedGradeLabel(grade),
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
        .foregroundStyle(theme.primaryText)

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
              .foregroundStyle(theme.accent)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(theme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(theme.controlBorder, lineWidth: 1)
        }
      } else {
        Button {
          date = defaultDate
        } label: {
          HStack {
            Text(LocalizationSupport.localized("Set date of birth"))
              .font(.system(size: 17))
              .foregroundStyle(theme.secondaryText)

            Spacer()

            PlatformIcon(
              systemName: "calendar",
              size: 14,
              weight: .semibold,
              color: theme.secondaryText
            )
          }
          .padding(.horizontal, 16)
          .frame(height: 56)
          .background(theme.fieldBackground)
          .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
              .stroke(theme.controlBorder, lineWidth: 1)
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
        .foregroundStyle(theme.primaryText)

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
            .foregroundStyle(selectedGrade.isEmpty ? theme.secondaryText : theme.primaryText)

          Spacer()

          PlatformIcon(
            systemName: "chevron.down",
            size: 12,
            weight: .semibold,
            color: theme.secondaryText
          )
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(theme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 15, style: .continuous)
            .stroke(theme.controlBorder, lineWidth: 1)
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
	VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.primaryText)

        Spacer()

        Text(selectedCurrency)
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(theme.secondaryText)
          .padding(.horizontal, 10)
          .frame(height: 24)
          .background(theme.controlBorder.opacity(0.7))
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
        .foregroundStyle(theme.primaryText)
        .padding(.horizontal, 18)
        .frame(height: 34)
        .background(isSelected ? theme.accent : theme.accentBackground)
        .clipShape(Capsule())
        .overlay {
          Capsule()
            .stroke(isSelected ? theme.accent : theme.controlBorder, lineWidth: 1)
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
      .foregroundStyle(theme.primaryText)
      .padding(.horizontal, 14)
      .frame(height: 34)
      .background(isSelected ? theme.accent : theme.accentBackground)
      .clipShape(Capsule())
      .overlay {
        Capsule()
          .stroke(isSelected ? theme.accent : theme.controlBorder, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }
}

struct ProfileEditInfoRow: View {
  @Binding var parameter: Parameter
  var isValid = true
  var errorMessage: String?

  var body: some View {
    AuthInputField(
      title: parameter.description,
      placeholder: parameter.description,
      systemImage: parameter.image,
      text: $parameter.value,
      keyboardType: keyboardType,
      textContentType: textContentType,
      isValid: isValid,
      errorMessage: errorMessage
    )
	.disabled(textContentType == .emailAddress)
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
		  .foregroundStyle(theme.primaryText)

		Text(state.subtitle)
		  .font(.system(size: 13))
		  .foregroundStyle(iconColor)
	  }

	  Spacer()

	  Button(action: action) {
		Text(state.actionTitle)
		  .font(.system(size: 14, weight: .bold))
		  .foregroundStyle(theme.primaryText)
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
	HStack(spacing: 10) {
	  FlatIconTile(systemName: parameter.image, size: 28)

	  Text(parameter.description)
		.font(.system(size: 13))
		.foregroundStyle(theme.secondaryText)

	  Spacer()

	  if isEditing {
		TextField(parameter.description, text: $parameter.value)
		  .font(.system(size: 15, weight: .semibold))
		  .foregroundStyle(theme.primaryText)
		  .lineLimit(1)
		  .minimumScaleFactor(0.75)
		  .multilineTextAlignment(.trailing)
		  .environment(\.layoutDirection, .leftToRight)
	  } else {
		Text(parameter.value.isEmpty ? "-" : parameter.value)
		  .font(.system(size: 15, weight: .semibold))
		  .foregroundStyle(theme.primaryText)
		  .lineLimit(1)
		  .minimumScaleFactor(0.75)
	  }
	}
	.padding(.horizontal, 16)
	.padding(.vertical, 14)
  }
}

#if !os(Android)
#Preview("Teacher Profile") {
  let vm = ProfileViewModel(roleType: .teacher, repository: ProfileRepository())
  vm.name = "Dr. Miri Cohen"
  vm.role = "Mathematics"
  vm.email = "miri@gmail.com"
  vm.phoneNumber = "0521234567"
  vm.username = "miri"
  vm.rating = 4.9
  vm.reviewCount = 128
  vm.subjects = ["Math", "Algebra", "Calculus"]
  vm.grade = "Grade 9, Grade 10, Grade 11"
  vm.hasMissingDocuments = false
  vm.cancelProfileEditing()
  return ProfileView(viewModel: vm)
}

#Preview("Teacher Profile - Hebrew") {
  let vm = ProfileViewModel(roleType: .teacher, repository: ProfileRepository())
  vm.name = "ד\"ר מירי כהן"
  vm.role = "מתמטיקה"
  vm.email = "miri@gmail.com"
  vm.phoneNumber = "0521234567"
  vm.username = "miri"
  vm.rating = 4.9
  vm.reviewCount = 128
  vm.subjects = ["מתמטיקה", "אלגברה", "חדו\"א"]
  vm.grade = "Grade 9, Grade 10, Grade 11"
  vm.hasMissingDocuments = false
  vm.cancelProfileEditing()
  return ProfileView(viewModel: vm)
    .environment(\.locale, Locale(identifier: "he"))
    .environment(\.layoutDirection, .rightToLeft)
}
#Preview("Student Profile") {
  let vm = ProfileViewModel(roleType: .student, repository: ProfileRepository())
  vm.name = "Alex Ben-David"
  vm.role = "Student"
  vm.email = "alex@gmail.com"
  vm.phoneNumber = "0541112233"
  vm.username = "alex"
  vm.cancelProfileEditing()
  return ProfileView(viewModel: vm)
}
#endif
