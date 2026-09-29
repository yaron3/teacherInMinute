//
//  StudentProfileView.swift
//  teacher-minute
//
//  Instant Teacher's profile, as its design draws it: who the student is, how
//  to reach them, and the device permissions a lesson needs. It runs on the
//  `ProfileViewModel` that `MainTabView` holds, as `ProfileView` does, and
//  edits through the same `ProfileEditView`.
//

import SwiftUI

struct StudentProfileView: View {
  /// `@Bindable`, not `@State`, for the reason `ProfileView` gives: the view
  /// model belongs to `MainTabView`.
  @Bindable var viewModel: ProfileViewModel
  @State var isShowingProfileEditor = false
#if os(Android)
  @State var isShowingPhotoSourceDialog = false
#endif
  @AppStorage(LocalizationSupport.languagePreferenceKey) var languagePreference = SettingsLanguageChoice.system.rawValue
  @Environment(\.scenePhase) var scenePhase

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
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
    }
  }

  // Split out of `body`, which the type checker would otherwise have to solve
  // in one piece.
  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 16) {
        BrandPageHero(title: viewModel.profileScreenTitle, subtitle: viewModel.profileSubtitle)
        if let error = viewModel.errorMessage {
          Text(error)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(theme.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        identityCard
      }
      .padding(.top, 16)
      .padding(.bottom, 20)

      contactCard
        .padding(.bottom, 16)

      permissionsCard
        .padding(.bottom, 16)
    }
    .padding(.horizontal, 20)
  }

  // MARK: - Identity

  /// The photo at the start, then the name and role. "Edit" at the far end
  /// is not in the design: it keeps the name, phone, grade and date of birth
  /// editable, as they are in the standard profile.
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
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        viewModel.editProfile()
        isShowingProfileEditor = true
      } label: {
        Text(viewModel.editLabel)
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(theme.brandActionBackground)
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("profile_edit_button")
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
    .confirmationDialog(
      viewModel.addPhotoDialogTitle,
      isPresented: $isShowingPhotoSourceDialog,
      titleVisibility: .visible
    ) {
      Button(viewModel.takePhotoLabel) {
        viewModel.pickProfilePhoto(fromCamera: true)
      }
      Button(viewModel.chooseFromLibraryLabel) {
        viewModel.pickProfilePhoto(fromCamera: false)
      }
      Button(viewModel.cancelLabel, role: .cancel) {}
    }
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
}

#if os(iOS)
struct StudentProfileView_Previews: PreviewProvider {
  static var previews: some View {
    StudentProfileView(viewModel: ProfileViewModel(roleType: .student))
  }
}
#endif
