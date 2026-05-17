//
//  TeacherSubjectsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct TeacherSubjectsView: View {
  @State var viewModel = TeacherSubjectsViewModel()
  var isEditing = false
  @Environment(\.appRouter) var router
  @Environment(\.dismiss) var dismiss
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	ScrollView {
	  VStack(alignment: .leading, spacing: 0) {
		if !isEditing {
		  Text("Step 2 of 2")
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(theme.authSecondaryText)
			.frame(maxWidth: .infinity)
		}
		
			Text("What can you teach?")
			  .font(.system(size: 26, weight: .bold))
			  .foregroundStyle(theme.authPrimaryText)
			  .padding(.top, 20)
			
			Text("Choose a subject area, then select at least\none subtopic students can request.")
			  .font(.system(size: 13))
			  .foregroundStyle(theme.authSecondaryText)
			  .lineSpacing(5)
			  .padding(.top, 8)
		
		searchField
		  .padding(.top, 24)
		
		HStack {
			  Text("Subject Area")
				.font(.system(size: 15, weight: .bold))
				.foregroundStyle(theme.authPrimaryText)
		  
		  Spacer()
		  
		  Text(viewModel.selectedCountText)
			.font(.system(size: 11, weight: .semibold))
			.foregroundStyle(theme.authSecondaryText)
			.padding(.horizontal, 10)
			.frame(height: 24)
			.background(theme.authFieldBorder.opacity(0.7))
			.clipShape(Capsule())
			}
			.padding(.top, 28)
			
				FlowLayout(spacing: 10) {
				  ForEach(viewModel.visibleAreas) { area in
					SubjectAreaChip(
					  area: area,
					  isSelected: viewModel.isAreaSelected(area)
					) {
					  viewModel.toggleArea(area)
					}
				  }
				}
				.padding(.top, 16)
				
				if viewModel.shouldShowSubtopicsPrompt {
				  Text("Choose one or more subjects to see subtopics.")
					.font(.system(size: 13))
					.foregroundStyle(theme.authSecondaryText)
					.padding(.top, 24)
				} else {
				  VStack(alignment: .leading, spacing: 22) {
					ForEach(viewModel.selectedAreas) { area in
					  VStack(alignment: .leading, spacing: 12) {
						HStack {
						  Text("\(area.title) subtopics")
							.font(.system(size: 15, weight: .bold))
							.foregroundStyle(theme.authPrimaryText)
						  
						  Spacer()
						  
						  Text(viewModel.selectedSubtopicTitles(for: area).isEmpty ? "Required" : "\(viewModel.selectedSubtopicTitles(for: area).count) selected")
							.font(.system(size: 11, weight: .semibold))
							.foregroundStyle(theme.authSecondaryText)
							.padding(.horizontal, 10)
							.frame(height: 24)
							.background(theme.authFieldBorder.opacity(0.7))
							.clipShape(Capsule())
						}
						
						FlowLayout(spacing: 10) {
						  ForEach(viewModel.visibleSubtopics(for: area)) { subtopic in
							SubjectChip(
							  subject: subtopic,
							  isSelected: viewModel.isSubtopicSelected(subtopic, in: area)
							) {
							  viewModel.toggleSubtopic(subtopic, in: area)
							}
						  }
						}
					  }
					}
				  }
				  .padding(.top, 28)
				}
			Spacer()
			AuthPrimaryButton(
		  title: isEditing ? "Save Changes" : "Continue to Onboarding",
		  systemImage: isEditing ? "checkmark" : "arrow.right",
		  isEnabled: viewModel.canContinue
		) {
		  viewModel.continueOnboarding()
			}
			.padding(.top, 32)
			.padding(.bottom, 24)
		  }
	  .padding(.horizontal, 18)
	}
	.background(Color(.systemBackground))
	.navigationBarTitleDisplayMode(.inline)
	.onAppear {
	  if isEditing {
		viewModel.onContinue = { dismiss() }
		viewModel.loadSelections()
	  } else {
		viewModel.onContinue = { router.push(.completeProfile(role: .teacher)) }
		viewModel.checkAndAutoAdvance()
	  }
	}
	.navigationTitle(isEditing ? LocalizationSupport.localized("Edit Subjects") : "")
	.toolbar {
	  if isEditing {
		ToolbarItem(placement: .cancellationAction) {
		  Button("Cancel") { dismiss() }
		}
	  }
	}
	.overlay {
	  if viewModel.isCheckingCompletion {
		ZStack {
		  theme.appPrimaryText.opacity(0.25).ignoresSafeArea()
		  VStack(spacing: 12) {
			ProgressView().progressViewStyle(.circular).scaleEffect(1.6).tint(theme.appPrimaryText)
			Text("Checking your subjects…")
			  .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.appPrimaryText)
		  }
		}
	  }
	}
  }
  
  var searchField: some View {
	HStack(spacing: 10) {
	  PlatformIcon(
		systemName: "magnifyingglass",
		size: 14,
		color: theme.authIcon
	  )
	  
	  TextField("Search subjects or subtopics", text: $viewModel.searchText)
		.font(.system(size: 13))
		.foregroundStyle(theme.authPrimaryText)
		.textInputAutocapitalization(.never)
		.autocorrectionDisabled()
	}
	.padding(.horizontal, 16)
	.frame(height: 44)
	.background(theme.appCardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 13, style: .continuous)
		.stroke(theme.authFieldBorder, lineWidth: 1)
	}
	.shadow(color: theme.appPrimaryText.opacity(0.03), radius: 10, x: 0, y: 4)
  }
}

struct SubjectAreaChip: View {
  let area: TeachingSubjectArea
  let isSelected: Bool
  let action: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	Button(action: action) {
	  HStack(spacing: 7) {
		PlatformIcon(systemName: area.systemImage)
		  .font(.system(size: 12, weight: .semibold))
		
		Text(area.title)
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
