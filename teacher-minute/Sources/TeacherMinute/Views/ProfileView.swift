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

/// The profile, on the brand's tab screen: who the user is, how to reach them,
/// and the device permissions a lesson needs. A teacher's also holds where
/// their payouts go, the grades and subjects they teach, and their documents.
/// It runs on the `ProfileViewModel` that `MainTabView` holds, and edits
/// through `ProfileEditView`.
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
#if os(Android)
  @State var isShowingPhotoSourceDialog = false
#endif
  @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
  @Environment(\.scenePhase) var scenePhase

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(viewModel: ProfileViewModel = ProfileViewModel()) {
    self.viewModel = viewModel
  }

  var body: some View {
    // A plain stack around the screen, for the photo chooser below.
    ZStack {
      screen
    }
#if os(Android)
    // The brand's dialog, as iOS's photo chooser is. Here rather than on the
    // photo button or inside the screen: on Android an `appDialog` is an
    // overlay, laid out within the view it is attached to, and this one must
    // dim the tab bar too.
    .appDialog(
      viewModel.addPhotoDialogTitle,
      isPresented: $isShowingPhotoSourceDialog,
      actions: [
        AppDialogAction(viewModel.takePhotoLabel) {
          viewModel.pickProfilePhoto(fromCamera: true)
        },
        AppDialogAction(viewModel.chooseFromLibraryLabel) {
          viewModel.pickProfilePhoto(fromCamera: false)
        },
        AppDialogAction(viewModel.cancelLabel, kind: .cancel)
      ]
    )
#endif
  }

  private var screen: some View {
    BrandTabScreen {
      VStack(spacing: 0) {
        BrandPageHeader(label: viewModel.profileScreenTitle, title: viewModel.profileDisplayName) {
          BrandMenuButton()
        }
        ScrollView(.vertical, showsIndicators: false) {
          content
        }
      }
      // On a plain stack inside the screen, not on `BrandTabScreen`; see
      // there.
      .task {
        if !viewModel.hasDisplayableProfileData {
          await viewModel.loadProfile()
        }
      }
      .onChange(of: scenePhase) { _, phase in
        guard phase == .active else { return }
        Task { await viewModel.refreshPermissionStates() }
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
  }

  // Split out of `body`, which the type checker would otherwise have to solve
  // in one piece.
  private var content: some View {
    VStack(alignment: .leading, spacing: 16) {
      BrandPageHero(title: viewModel.profileScreenTitle, subtitle: viewModel.profileSubtitle)
      if let error = viewModel.errorMessage {
        loadError(error)
      }
      identityCard
      contactCard
      if viewModel.shouldShowTeacherPaymentsMethod {
        payoutMethodCard
      }
      if viewModel.shouldShowTeachingDetails {
        teachingDetails
      }
      permissionsCard
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 20)
  }

  /// Shown above the profile when a load failed, rather than in place of it:
  /// the fields keep their placeholders, which is still a usable screen.
  private func loadError(_ error: String) -> some View {
    HStack(spacing: 12) {
      Text(error)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(theme.danger)
        .frame(maxWidth: .infinity, alignment: .leading)
      Button {
        Task { await viewModel.loadProfile() }
      } label: {
        Text(viewModel.retryLabel)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(theme.brandActionBackground)
      }
      .buttonStyle(.plain)
    }
  }

  // MARK: - Identity

  /// The photo at the start, then the name, the role and, for a rated
  /// teacher, the rating. "Edit" at the far end keeps the details editable.
  private var identityCard: some View {
    HStack(spacing: 12) {
      avatar
      VStack(alignment: .leading, spacing: 4) {
        Text(viewModel.profileDisplayName)
          .font(.system(size: 22, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        Text(viewModel.role)
          .font(.system(size: 15))
          .foregroundStyle(theme.brandSecondaryText)
          .lineLimit(1)
        if viewModel.hasRating {
          HStack(spacing: 4) {
            Text(LessonFormatting.ratingText(viewModel.rating))
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(theme.onDarkFill)
            RatingStarsView(rating: viewModel.rating, size: 12)
            Text(viewModel.reviewCountText)
              .font(.system(size: 12))
              .foregroundStyle(theme.brandSecondaryText)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      editButton(identifier: "profile_edit_button") {
        showProfileEditor()
      }
    }
    .brandCard()
  }

  /// The photo, with the button that changes it overlapping its lower
  /// outside corner.
  private var avatar: some View {
    ZStack(alignment: .bottomLeading) {
      avatarCircle
        .frame(width: 100, height: 86, alignment: .trailing)
      photoButton
    }
    .frame(width: 100, height: 86)
  }

  private var avatarCircle: some View {
    ZStack {
      Circle()
        .fill(theme.onDarkFill)
      if viewModel.profileImageURL.isEmpty {
        Image(decorative: "brand-avatar-placeholder", bundle: .module)
          .resizable()
          .frame(width: 36, height: 36)
      } else {
        CachedRemoteImage(url: viewModel.profileImageURL, contentMode: .fill)
          .frame(width: 86, height: 86)
          .clipShape(Circle())
      }
    }
    .frame(width: 86, height: 86)
  }

  @ViewBuilder
  private var photoButton: some View {
#if !os(Android)
    PhotoSourceButton(viewModel: viewModel, onImageData: { data in
      viewModel.uploadProfileImage(data: data)
    }) {
      captureBadge
    }
    .accessibilityIdentifier("profile_photo_button")
#else
    Button {
      isShowingPhotoSourceDialog = true
    } label: {
      captureBadge
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("profile_photo_button")
#endif
  }

  private var captureBadge: some View {
    ZStack {
      Circle()
        .fill(theme.brandActionBackground)
      if viewModel.isUploadingPhoto {
        ProgressView()
          .scaleEffect(0.7)
          .tint(theme.onBrandAction)
      } else {
        Image("brand-capture", bundle: .module)
          .renderingMode(.template)
          .resizable()
          .foregroundStyle(theme.onBrandAction)
          .frame(width: 24, height: 24)
      }
    }
    .frame(width: 40, height: 40)
  }

  private func editButton(identifier: String, action: @escaping () -> Void) -> some View {
    Button {
      action()
    } label: {
      Text(viewModel.editLabel)
        .font(.system(size: 14, weight: .bold))
        .foregroundStyle(theme.brandActionBackground)
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier(identifier)
  }

  // MARK: - Contact

  private var contactCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      contactRow(label: viewModel.emailFieldLabel, value: viewModel.email)
      BrandRule()
      contactRow(label: viewModel.phoneFieldLabel, value: viewModel.phoneNumber)
    }
    .brandCard()
  }

  private func contactRow(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.system(size: 13))
        .foregroundStyle(theme.brandSecondaryText)
      Text(value.isEmpty ? "-" : value)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - A teacher's

  /// Where the teacher's payouts go.
  private var payoutMethodCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Text(viewModel.paymentMethodLabel)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .frame(maxWidth: .infinity, alignment: .leading)
        editButton(identifier: "profile_payout_edit_button") {
          showProfileEditor()
        }
      }
      HStack(spacing: 12) {
        FlatIconTile(systemName: viewModel.payoutMethodSystemImage, size: 40)
        VStack(alignment: .leading, spacing: 4) {
          Text(viewModel.payoutMethodTitle)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.onDarkFill)
          Text(viewModel.payoutMethodDetail)
            .font(.system(size: 13))
            .foregroundStyle(viewModel.hasPayoutMethod ? theme.onDarkFill : theme.brandSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .brandCard()
  }

  /// The grades and subjects the teacher teaches, and their documents.
  private var teachingDetails: some View {
    VStack(alignment: .leading, spacing: 12) {
      FlatSectionHeader(viewModel.teachingDetailsSectionTitle)
        .padding(.top, 8)

      teachingCard(
        title: viewModel.gradeLevelsTaughtTitle,
        chips: viewModel.gradeLevelLabels,
        includeAdd: viewModel.gradeLevels.isEmpty
      ) {
        showProfileEditor()
      }

      teachingCard(
        title: viewModel.subjectsSectionTitle,
        chips: viewModel.subjectsOrPlaceholder,
        includeAdd: viewModel.subjects.isEmpty
      ) {
        isShowingSubjectEditor = true
      }

      documentsButton
    }
  }

  private func teachingCard(
    title: String,
    chips: [String],
    includeAdd: Bool,
    edit: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(title)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(theme.brandSecondaryText)
        Spacer()
        editButton(identifier: "profile_teaching_edit_button") {
          edit()
        }
      }

      ChipGrid(minimumItemWidth: 96, spacing: 8) {
        ForEach(chips, id: \.self) { chip in
          FlatChip(title: chip, outlined: true)
        }

        if includeAdd {
          Button {
            edit()
          } label: {
            FlatChip(title: viewModel.addChipLabel, outlined: true)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .brandCard()
  }

  private var documentsButton: some View {
    Button {
      isShowingDocuments = true
    } label: {
      HStack(spacing: 14) {
        FlatIconTile(systemName: viewModel.hasMissingDocuments ? "doc.badge.plus" : "doc.text.fill", size: 44)

        VStack(alignment: .leading, spacing: 3) {
          Text(viewModel.hasMissingDocuments
               ? viewModel.completeDocumentsTitle
               : viewModel.documentsUploadedTitle)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(theme.onDarkFill)

          Text(viewModel.hasMissingDocuments
               ? viewModel.uploadRemainingDocumentsSubtitle
               : viewModel.viewUploadedDocumentsSubtitle)
            .font(.system(size: 13))
            .foregroundStyle(theme.brandSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        BrandForwardChevron()
      }
      .brandCard()
      .tappableFrame()
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("profile_documents_button")
  }

  // MARK: - Permissions

  private var permissionsCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(viewModel.devicePermissionsSectionTitle)
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .frame(maxWidth: .infinity, alignment: .leading)

      permissionRow(
        title: viewModel.microphoneLabel,
        state: viewModel.microphoneState,
        identifier: "microphone"
      ) {
        viewModel.microphoneToggleTapped()
      }
      BrandRule()
      permissionRow(
        title: viewModel.cameraLabel,
        state: viewModel.cameraState,
        identifier: "camera"
      ) {
        viewModel.cameraToggleTapped()
      }
      BrandRule()
      permissionRow(
        title: viewModel.notificationsLabel,
        state: viewModel.notificationsState,
        identifier: "notifications"
      ) {
        viewModel.manageNotifications()
      }
    }
    .brandCard()
  }

  /// The permission and its state, then its switch at the far end.
  private func permissionRow(
    title: String,
    state: PermissionState,
    identifier: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
        Text(state.subtitle)
          .font(.system(size: 13))
          .foregroundStyle(theme.brandActionBackground)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      BrandToggle(isOn: state.isGranted, action: action)
        .accessibilityIdentifier("permission_toggle_\(identifier)")
    }
  }

  private func showProfileEditor() {
    viewModel.editProfile()
    isShowingProfileEditor = true
  }
}

struct ProfileEditView: View {
  @State var viewModel: ProfileViewModel
  @Environment(\.dismiss) var dismiss
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  /// The fields, as the brand's, in a brand card on a brand sheet.
  var body: some View {
    ZStack {
      BrandSheet(title: viewModel.editProfileTitle, closeLabel: viewModel.cancelLabel) {
        viewModel.cancelProfileEditing()
        dismiss()
      } content: {
        Text(viewModel.editProfileSubtitle)
          .font(.system(size: 15))
          .foregroundStyle(theme.brandSecondaryText)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 16) {
          fields

          if let error = viewModel.errorMessage {
            Text(error)
              .font(.system(size: 12))
              .foregroundStyle(theme.danger)
          }

          BrandPrimaryButton(
            title: viewModel.saveButtonLabel,
            isLoading: viewModel.isLoading,
            isEnabled: viewModel.canSaveProfileEdits
          ) {
            viewModel.saveProfileEdits()
          }
        }
        .brandCard()
      }
    }
    .toolbar(.hidden, for: .navigationBar)
    .onChange(of: viewModel.isEditing) { _, isEditing in
      if !isEditing {
        dismiss()
      }
    }
  }

  var fields: some View {
        VStack(spacing: 16) {
          ForEach($viewModel.contactRows, id: \.description) { $row in
            if viewModel.roleType == .student && row.description == viewModel.gradeFieldLabel {
              ProfileGradePicker(
                viewModel: viewModel,
                title: row.description,
                selectedGrade: $row.value,
                grades: viewModel.availableStudentGrades
              )
            } else if viewModel.roleType == .student && row.description == viewModel.dateOfBirthFieldLabel {
              ProfileDateOfBirthPicker(
                viewModel: viewModel,
                title: row.description,
                date: $viewModel.dateOfBirth
              )
            } else {
              ProfileEditInfoRow(
                viewModel: viewModel,
                parameter: $row,
                isValid: viewModel.isRowValid(row),
                errorMessage: viewModel.rowErrorMessage(for: row),
				
              )
            }
          }

          if viewModel.roleType == .teacher {
            ProfileTeachingGradePicker(
              viewModel: viewModel,
              title: viewModel.gradeLevelsTaughtTitle,
              selectedGrades: $viewModel.selectedTeachingGrades
            )
          }
        }
  }
}

struct ProfileTeachingGradePicker: View {
  let viewModel: ProfileViewModel
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

        Text(selectedGrades.isEmpty ? viewModel.chooseGradesLabel : viewModel.selectedGradesCountText(selectedGrades.count))
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
			  title: viewModel.gradeLabel(for: grade),
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
  let viewModel: ProfileViewModel
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
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(theme.brandSecondaryText)

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
            Text(viewModel.clearLabel)
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(theme.accent)
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(theme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(theme.controlBorder, lineWidth: 1)
        }
      } else {
        Button {
          date = defaultDate
        } label: {
          HStack {
            Text(viewModel.setDateOfBirthLabel)
              .font(.system(size: 17))
              .foregroundStyle(theme.secondaryText)

            Spacer()

            // A symbol SkipUI draws as a Material icon; PlatformIcon puts an
            // emoji here on Android.
            Image(systemName: "calendar")
              .resizable()
              .scaledToFit()
              .foregroundStyle(theme.secondaryText)
              .frame(width: 18, height: 18)
          }
          .padding(.horizontal, 12)
          .frame(height: 52)
          .background(theme.fieldBackground)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
              .stroke(theme.controlBorder, lineWidth: 1)
          }
        }
        .buttonStyle(.plain)
      }
    }
  }
}

struct ProfileGradePicker: View {
  let viewModel: ProfileViewModel
  let title: String
  @Binding var selectedGrade: String
  let grades: [String]
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.system(size: 16, weight: .bold))
        .foregroundStyle(theme.brandSecondaryText)

      Menu {
        ForEach(grades, id: \.self) { grade in
          Button(grade) {
            selectedGrade = grade
          }
        }
      } label: {
        HStack {
          Text(selectedGrade.isEmpty ? viewModel.selectLabel : selectedGrade)
            .font(.system(size: 17))
            .foregroundStyle(selectedGrade.isEmpty ? theme.secondaryText : theme.primaryText)

          Spacer()

          // A symbol SkipUI draws as a Material icon; PlatformIcon puts an
          // emoji here on Android.
          Image(systemName: "chevron.down")
            .resizable()
            .scaledToFit()
            .foregroundStyle(theme.secondaryText)
            .frame(width: 16, height: 16)
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .background(theme.fieldBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
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

        Text(title)
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
  let viewModel: ProfileViewModel
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
    case viewModel.emailFieldLabel:
      return .emailAddress
    case viewModel.phoneFieldLabel:
      return .phonePad
    default:
      return .default
    }
  }

  private var textContentType: UITextContentType? {
    switch parameter.description {
    case viewModel.fullNameFieldLabel:
      return .name
    case viewModel.emailFieldLabel:
      return .emailAddress
    case viewModel.phoneFieldLabel:
      return .telephoneNumber
    default:
      return nil
    }
  }
}

#if os(Android)
enum AndroidProfileImagePickerBridge {
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
