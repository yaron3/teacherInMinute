//
//  TeacherSubjectsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct TeacherSubjectsView: View {
  @State var viewModel = TeacherSubjectsViewModel()
  @Environment(\.appRouter) var router
  
  var body: some View {
	ScrollView {
	  VStack(alignment: .leading, spacing: 0) {
		Text("Step 2 of 2")
		  .font(.system(size: 13, weight: .medium))
		  .foregroundStyle(Color.authSecondaryText)
		  .frame(maxWidth: .infinity)
		
		Text("What can you teach?")
		  .font(.system(size: 26, weight: .bold))
		  .foregroundStyle(Color.authPrimaryText)
		  .padding(.top, 20)
		
		Text("Select the math subjects you are comfortable\nteaching. Students will see these on your profile.")
		  .font(.system(size: 13))
		  .foregroundStyle(Color.authSecondaryText)
		  .lineSpacing(5)
		  .padding(.top, 8)
		
		searchField
		  .padding(.top, 24)
		
		HStack {
		  Text("Popular Subjects")
			.font(.system(size: 15, weight: .bold))
			.foregroundStyle(Color.authPrimaryText)
		  
		  Spacer()
		  
		  Text(viewModel.selectedCountText)
			.font(.system(size: 11, weight: .semibold))
			.foregroundStyle(Color.authSecondaryText)
			.padding(.horizontal, 10)
			.frame(height: 24)
			.background(Color.authFieldBorder.opacity(0.7))
			.clipShape(Capsule())
		}
		.padding(.top, 28)
		
		FlowLayout(spacing: 10) {
		  ForEach(viewModel.popularSubjects) { subject in
			SubjectChip(
			  subject: subject,
			  isSelected: viewModel.selectedSubjects.contains(subject)
			) {
			  viewModel.toggle(subject)
			}
		  }
		}
		.padding(.top, 16)
		
		Text("Advanced Topics")
		  .font(.system(size: 15, weight: .bold))
		  .foregroundStyle(Color.authPrimaryText)
		  .padding(.top, 32)
		
		FlowLayout(spacing: 10) {
		  ForEach(viewModel.advancedSubjects) { subject in
			SubjectChip(
			  subject: subject,
			  isSelected: viewModel.selectedSubjects.contains(subject)
			) {
			  viewModel.toggle(subject)
			}
		  }
		}
		.padding(.top, 16)
		
		AuthPrimaryButton(
		  title: "Continue to Onboarding",
		  systemImage: "arrow.right",
		  isEnabled: viewModel.canContinue
		) {
		  viewModel.continueOnboarding()
		}
		.padding(.top, 32)
		
		Button {
		  viewModel.skip()
		} label: {
		  Text("Skip for now")
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(Color.authSecondaryText)
			.frame(maxWidth: .infinity)
		}
		.buttonStyle(.plain)
		.padding(.top, 18)
		.padding(.bottom, 24)
	  }
	  .padding(.horizontal, 18)
	}
	.background(Color(.systemBackground))
	.navigationBarTitleDisplayMode(.inline)
	.onAppear {
	  viewModel.onContinue = { router.push(.completeProfile(role: .teacher)) }
	}
  }
  
  var searchField: some View {
	HStack(spacing: 10) {
	  Image(systemName: "magnifyingglass")
		.font(.system(size: 14))
		.foregroundStyle(Color.authIcon)
	  
	  TextField("Search subjects (e.g. Calculus)", text: $viewModel.searchText)
		.font(.system(size: 13))
		.foregroundStyle(Color.authPrimaryText)
		.textInputAutocapitalization(.never)
		.autocorrectionDisabled()
	}
	.padding(.horizontal, 16)
	.frame(height: 44)
	.background(.white)
	.clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 13, style: .continuous)
		.stroke(Color.authFieldBorder, lineWidth: 1)
	}
	.shadow(color: .black.opacity(0.03), radius: 10, x: 0, y: 4)
  }
}
