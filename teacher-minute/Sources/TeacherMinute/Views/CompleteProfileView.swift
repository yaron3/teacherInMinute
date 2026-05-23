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
	  Text(LocalizationSupport.localized("Complete your profile"))
		.font(.system(size: 26, weight: .bold))
		.foregroundStyle(theme.authPrimaryText)
		.padding(.top, 42)
	  
	  Text(LocalizationSupport.localized("Tell us a bit about yourself to get started with\nMath Connect."))
		.font(.system(size: 13))
		.foregroundStyle(theme.authSecondaryText)
		.lineSpacing(5)
		.padding(.top, 10)
	  
	  AuthInputField(
		title: LocalizationSupport.localized("Full Name"),
		placeholder: LocalizationSupport.localized("place holder name"),
		systemImage: "person",
		text: $viewModel.fullName,
		textContentType: .name
	  )
	  .padding(.top, 28)

	  AuthInputField(
		title: viewModel.role == .student
		  ? LocalizationSupport.localized("Phone Number (Optional)")
		  : LocalizationSupport.localized("Phone Number"),
		placeholder: LocalizationSupport.localized("place holder phone number"),
		systemImage: "phone",
		text: $viewModel.phoneNumber,
		keyboardType: .phonePad,
		textContentType: .telephoneNumber
	  )
	  .padding(.top, 20)

	  if viewModel.role == .student {
			HStack(spacing: 12) {
			  dobPicker
			  gradePicker
			}
			.padding(.top, 20)
	  } else {
			AuthInputField(
			  title: LocalizationSupport.localized("PayPal Email"),
			  placeholder: LocalizationSupport.localized("Optional"),
			  systemImage: "p.circle.fill",
			  text: $viewModel.paypalEmail,
			  keyboardType: .emailAddress,
			  textContentType: .emailAddress
			)
			.padding(.top, 20)
	  }
	  
	  Spacer()
	  
	  if let error = viewModel.errorMessage {
		Text(error)
		  .font(.system(size: 12))
		  .foregroundStyle(.red)
		  .padding(.bottom, 8)
	  }
	  
	  AuthPrimaryButton(
		title: LocalizationSupport.localized("Continue"),
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
		router.enterMainTabs(role: viewModel.role)
	  }
	  viewModel.checkAndAutoAdvance()
	}
	.onChange(of: viewModel.dateOfBirth) { _, _ in
	  viewModel.suggestGradeFromDOB()
	}
	.onChange(of: viewModel.grade) { _, _ in
	  viewModel.suggestDOBFromGrade()
	}
	.overlay {
	  if viewModel.isCheckingCompletion {
		ZStack {
		  theme.appPrimaryText.opacity(0.25).ignoresSafeArea()
		  VStack(spacing: 12) {
			ProgressView().progressViewStyle(.circular).scaleEffect(1.6).tint(theme.appPrimaryText)
			Text(LocalizationSupport.localized("Loading your profile…"))
			  .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.appPrimaryText)
		  }
		}
	  }
	}
	.alert(LocalizationSupport.localized("Payout Details Missing"), isPresented: $viewModel.showMissingPayoutInfoConfirmation) {
	  Button(LocalizationSupport.localized("Add Now"), role: .cancel) {}
	  Button(LocalizationSupport.localized("Continue Anyway")) {
		viewModel.continueWithoutPayoutInfo()
	  }
	} message: {
	  Text(LocalizationSupport.localized("You will not receive money until you provide bank account details or PayPal info."))
	}
  }
  
  var dobPicker: some View {
	VStack(alignment: .leading, spacing: 10) {
	  Text(LocalizationSupport.localized("Date of Birth"))
		.font(.system(size: 13, weight: .semibold))
		.foregroundStyle(theme.authPrimaryText)
	  
	  DatePicker(
		"",
		selection: $viewModel.dateOfBirth,
		in: Date.distantPast...viewModel.maxDateOfBirth,
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
	  Text(LocalizationSupport.localized("Your Grade"))
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
		  Text(viewModel.grade.isEmpty ? LocalizationSupport.localized("Select") : viewModel.grade)
			.font(.system(size: 15))
			.foregroundStyle(viewModel.grade.isEmpty ? theme.authSecondaryText : theme.authPrimaryText)
		  
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
