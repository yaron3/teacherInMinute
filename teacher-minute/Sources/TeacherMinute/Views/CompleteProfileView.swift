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
  
  init(viewModel: CompleteProfileViewModel = CompleteProfileViewModel(role: .student)) {
	self._viewModel = State(wrappedValue: viewModel)
  }
  
  var body: some View {
	VStack(alignment: .leading, spacing: 0) {
	  Text("Complete your profile")
		.font(.system(size: 26, weight: .bold))
		.foregroundStyle(Color.authPrimaryText)
		.padding(.top, 42)
	  
	  Text("Tell us a bit about yourself to get started with\nMath Connect.")
		.font(.system(size: 13))
		.foregroundStyle(Color.authSecondaryText)
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
		AuthInputField(
		  title: "Age",
		  placeholder: "16",
		  systemImage: "number",
		  text: $viewModel.age,
		  keyboardType: .numberPad
		)
		
		gradePicker
	  }
	  .padding(.top, 20)
	  
	  Spacer()
	  
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
		if viewModel.role == .teacher {
		  router.push(.teacherDashboard)
		} else {
		  router.push(.studentHome)
		}
	  }
	}
  }
  
  var gradePicker: some View {
	VStack(alignment: .leading, spacing: 10) {
	  Text("Your Grade")
		.font(.system(size: 13, weight: .semibold))
		.foregroundStyle(Color.authPrimaryText)
	  
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
			.foregroundStyle(viewModel.grade.isEmpty ? Color.authSecondaryText : Color.authPrimaryText)
		  
		  Spacer()
		  
		  Image(systemName: "chevron.down")
			.font(.system(size: 12, weight: .semibold))
			.foregroundStyle(Color.authIcon)
		}
		.padding(.horizontal, 16)
		.frame(height: 56)
		.background(.white)
		.clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
		.overlay {
		  RoundedRectangle(cornerRadius: 15, style: .continuous)
			.stroke(Color.authFieldBorder, lineWidth: 1)
		}
	  }
	}
  }
}
