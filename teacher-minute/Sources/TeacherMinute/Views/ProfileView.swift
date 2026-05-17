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
	  VStack(alignment: .leading, spacing: 0) {
		HStack {
		  Text("Profile")
			.font(.system(size: 24, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
		  
		  Spacer()
		  
		  Button {
			viewModel.editProfile()
		  } label: {
			Circle()
			  .fill(theme.appPrimaryText)
			  .frame(width: 42, height: 42)
			  .shadow(color: theme.appPrimaryText.opacity(0.05), radius: 12, x: 0, y: 6)
			  .overlay {
				PlatformIcon(systemName: viewModel.isEditing ? "checkmark" : "pencil", color: theme.appGreen)
				  .font(.system(size: 15, weight: .bold))
			  }
		  }
		  .buttonStyle(.plain)
		}
		.padding(.top, 24)
		
		profileHeader
		  .padding(.top, 26)
		
		Text("Account Info")
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
		  Text("Teaching Details")
			.font(.system(size: 16, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
			.padding(.top, 30)
		  
		  teachingCard(
			title: "Grade Levels Taught",
			chips: viewModel.gradeLevels,
			includeAdd: viewModel.gradeLevels.isEmpty,
			editAction: viewModel.editGradeLevels,
			addAction: viewModel.addGradeLevel
		  )
		  .padding(.top, 14)
		  
		  teachingCard(
			title: "Subjects",
			chips: viewModel.subjectsOrPlaceholder,
			includeAdd: viewModel.subjects.isEmpty,
			editAction: viewModel.editSubjects,
			addAction: viewModel.editSubjects
		  )
		  .padding(.top, 18)
		}
		
		Text("Device Permissions")
		  .font(.system(size: 16, weight: .bold))
		  .foregroundStyle(theme.appPrimaryText)
		  .padding(.top, 30)
		
			VStack(spacing: 14) {
			  ProfilePermissionRow(
				icon: "mic.fill",
				title: "Microphone",
				state: viewModel.microphoneState,
				iconColor: viewModel.microphoneState.isGranted ? theme.appGreen : theme.appSecondaryText,
                action: viewModel.requestMicrophonePermission
              )
			  
			  ProfilePermissionRow(
				icon: "camera.fill",
				title: "Camera",
				state: viewModel.cameraState,
				iconColor: viewModel.cameraState.isGranted ? theme.appGreen : theme.appSecondaryText,
                action: viewModel.requestCameraPermission
              )

			  ProfilePermissionRow(
				icon: "bell.fill",
				title: "Notifications",
				state: viewModel.notificationsState,
				iconColor: viewModel.notificationsState.isGranted ? theme.appGreen : theme.appSecondaryText,
                action: viewModel.manageNotifications
              )
			}
	  }
	  .padding(.horizontal, 18)
	  .padding(.bottom, 24)
	}
		.background(Color(.systemBackground))
		.task {
		  await viewModel.loadProfile()
		}
#if !os(Android)
        .onChange(of: profilePhotoItem) { _, item in
          loadProfilePhoto(item)
        }
#endif
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
		
		if viewModel.isVerified {
		  SmallPill(title: "Verified", foreground: theme.appGreen, background: theme.appGreenSoft)
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
			Text("Edit")
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
			  Text("+ Add")
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
			  .font(.system(size: 15, weight: .semibold))
			  .foregroundStyle(theme.appPurple)
		  }
		
		VStack(alignment: .leading, spacing: 4) {
		  Text(parameter.description)
			.font(.system(size: 12))
			.foregroundStyle(theme.appSecondaryText)
		  
		  TextField(parameter.description, text: $parameter.value)
			.font(.system(size: 14, weight: .bold))
			.foregroundStyle(theme.appPrimaryText)
			.lineLimit(1)
			.minimumScaleFactor(0.75)
			.disabled(!isEditing)
		}
		
		Spacer()
	  }
	}
  }
}
