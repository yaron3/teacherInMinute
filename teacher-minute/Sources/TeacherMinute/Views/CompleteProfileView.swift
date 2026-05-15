//
//  CompleteProfileView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct CompleteProfileView: View {
  @State var viewModel: CompleteProfileViewModel
  @Environment(\.appRouter) var router
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  init(viewModel: CompleteProfileViewModel = CompleteProfileViewModel(role: .student)) {
	self._viewModel = State(wrappedValue: viewModel)
  }
  
  var body: some View {
	VStack(alignment: .leading, spacing: 0) {
	  Text("Complete your profile")
		.font(.system(size: 26, weight: .bold))
		.foregroundStyle(theme.authPrimaryText)
		.padding(.top, 42)
	  
	  Text("Tell us a bit about yourself to get started with\nMath Connect.")
		.font(.system(size: 13))
		.foregroundStyle(theme.authSecondaryText)
		.lineSpacing(5)
		.padding(.top, 10)
	  
	  AuthSegmentedRolePicker(selectedRole: $viewModel.selectedRole)
		.padding(.top, 28)
	  
	  AuthInputField(
		title: "Full Name",
		placeholder: "John Doe",
		systemImage: "person",
		text: $viewModel.fullName,
		textContentType: .name
	  )
	  .padding(.top, 28)
	  
	  AuthInputField(
		title: "Phone Number",
		placeholder: "+1 (555) 000-0000",
		systemImage: "phone",
		text: $viewModel.phoneNumber,
		keyboardType: .phonePad,
		textContentType: .telephoneNumber
	  )
	  .padding(.top, 20)
	  
	  HStack(spacing: 12) {
		dobPicker
		gradePicker
	  }
	  .padding(.top, 20)
	  
	  Spacer()
	  
	  if let error = viewModel.errorMessage {
		Text(error)
		  .font(.system(size: 12))
		  .foregroundStyle(.red)
		  .padding(.bottom, 8)
	  }
	  
	  AuthPrimaryButton(
		title: "Continue",
		systemImage: "arrow.right",
		isEnabled: viewModel.canContinue
	  ) {
		viewModel.continueFlow()
	  }
	  .padding(.bottom, 24)
	}
	.padding(.horizontal, 18)
	.background(Color(.systemBackground))
	.navigationBarTitleDisplayMode(.inline)
	.onAppear {
	  viewModel.onContinue = {
		router.replace(with: .mainTabs(role: viewModel.role))
	  }
	  viewModel.checkAndAutoAdvance()
	}
	.overlay {
	  if viewModel.isCheckingCompletion {
		ZStack {
		  theme.appPrimaryText.opacity(0.25).ignoresSafeArea()
		  VStack(spacing: 12) {
			ProgressView().progressViewStyle(.circular).scaleEffect(1.6).tint(.white)
			Text("Loading your profile…")
			  .font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
		  }
		}
	  }
	}
  }
  
  var dobPicker: some View {
	VStack(alignment: .leading, spacing: 10) {
	  Text("Date of Birth")
		.font(.system(size: 13, weight: .semibold))
		.foregroundStyle(theme.authPrimaryText)
	  
	  DatePicker(
		"",
		selection: $viewModel.dateOfBirth,
		in: Date.distantPast...Date(),
		displayedComponents: .date
	  )
	  .labelsHidden()
#if !os(Android)
	  .datePickerStyle(.compact)
#endif
	  .frame(height: 56)
	  .padding(.horizontal, 12)
	  .background(theme.appCardBackground)
	  .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
	  .overlay {
		RoundedRectangle(cornerRadius: 15, style: .continuous)
		  .stroke(theme.authFieldBorder, lineWidth: 1)
	  }
	}
  }
  
  var gradePicker: some View {
	VStack(alignment: .leading, spacing: 10) {
	  Text("Your Grade")
		.font(.system(size: 13, weight: .semibold))
		.foregroundStyle(theme.authPrimaryText)
	  
	  Menu {
		ForEach(viewModel.grades, id: \.self) { grade in
		  Button(grade) {
			viewModel.grade = grade
		  }
		}
	  } label: {
		HStack {
		  Text(viewModel.grade.isEmpty ? "Select" : viewModel.grade)
			.font(.system(size: 15))
			.foregroundStyle(viewModel.grade.isEmpty ? theme.authSecondaryText : theme.authPrimaryText)
		  
		  Spacer()
		  
		  PlatformIcon(systemName: "chevron.down")
			.font(.system(size: 12, weight: .semibold))
			.foregroundStyle(theme.authIcon)
		}
		.padding(.horizontal, 16)
		.frame(height: 56)
		.background(theme.appCardBackground)
		.clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
		.overlay {
		  RoundedRectangle(cornerRadius: 15, style: .continuous)
			.stroke(theme.authFieldBorder, lineWidth: 1)
		}
	  }
	}
  }
}
