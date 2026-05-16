//
//  ProfileView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct ProfileView: View {
  @State var viewModel: ProfileViewModel
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  init(viewModel: ProfileViewModel = ProfileViewModel(subjects: [], roleType: .student, isEditing: false, contactRows: [])) {
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
			subtitle: "Enabled",
			iconColor: theme.appGreen,
			isToggle: true,
			isOn: $viewModel.microphoneEnabled
		  )
		  
		  ProfilePermissionRow(
			icon: "bell.fill",
			title: "Notifications",
			subtitle: "Disabled",
			iconColor: theme.appSecondaryText,
			isToggle: false,
			isOn: $viewModel.notificationsEnabled,
			actionTitle: "Manage"
		  ) {
			viewModel.manageNotifications()
		  }
		}
	  }
	  .padding(.horizontal, 18)
	  .padding(.bottom, 24)
	}
	.background(Color(.systemBackground))
	.task {
	  await viewModel.loadProfile()
	}
  }
  
  var profileHeader: some View {
	VStack(spacing: 0) {
	  ZStack(alignment: .bottomTrailing) {
		Circle()
		  .fill(theme.appPurpleSoft)
		  .frame(width: 96, height: 96)
		  .overlay {
			PlatformIcon(systemName: "person.crop.circle.fill")
			  .font(.system(size: 72))
			  .foregroundStyle(theme.appPurple)
		  }
		
		Button {
		  viewModel.changePhoto()
		} label: {
		  Circle()
			.fill(theme.appPink)
			.frame(width: 30, height: 30)
			.overlay {
			  PlatformIcon(systemName: "camera.fill")
				.font(.system(size: 12, weight: .bold))
				.foregroundStyle(theme.appPrimaryText)
			}
		}
		.buttonStyle(.plain)
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
}

struct ProfilePermissionRow: View {
  let icon: String
  let title: String
  let subtitle: String
  let iconColor: Color
  let isToggle: Bool
  @Binding var isOn: Bool
  var actionTitle: String?
  var action: (() -> Void)?
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
		  
		  Text(subtitle)
			.font(.system(size: 12, weight: .semibold))
			.foregroundStyle(iconColor)
		}
		
		Spacer()
		
		if isToggle {
		  Toggle("", isOn: $isOn)
			.labelsHidden()
			.tint(theme.appGreen)
		} else if let actionTitle {
		  Button {
			action?()
		  } label: {
			Text(actionTitle)
			  .font(.system(size: 13, weight: .semibold))
			  .foregroundStyle(theme.appPink)
		  }
		  .buttonStyle(.plain)
		}
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
