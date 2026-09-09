//
//  TeacherSubjectsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

@MainActor
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
		  Text(LocalizationSupport.localized("Step 2 of 2"))
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(theme.secondaryText)
			.frame(maxWidth: .infinity)
		}
		
		
		Text(LocalizationSupport.localized("Choose a subject area, then select at least\none subtopic students can request."))
		  .font(.system(size: 13))
		  .foregroundStyle(theme.secondaryText)
		  .lineSpacing(5)
		  .padding(.top, 8)
		
		searchField
		  .padding(.top, 24)
		
		HStack {
		  Text(LocalizationSupport.localized("Subject Area"))
			.font(.system(size: 15, weight: .bold))
			.foregroundStyle(theme.primaryText)
		  
		  Spacer()
		  
		  Text(viewModel.selectedCountText)
			.font(.system(size: 11, weight: .semibold))
			.foregroundStyle(theme.secondaryText)
			.padding(.horizontal, 10)
			.frame(height: 24)
			.background(theme.controlBorder.opacity(0.7))
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
		  Text(LocalizationSupport.localized("Choose one or more subjects to see subtopics."))
			.font(.system(size: 13))
			.foregroundStyle(theme.secondaryText)
			.padding(.top, 24)
		} else {
		  VStack(alignment: .leading, spacing: 22) {
			ForEach(viewModel.selectedAreas) { area in
			  VStack(alignment: .leading, spacing: 12) {
				HStack {
				  Text(String(format: LocalizationSupport.localized("%@ subtopics"), LocalizationSupport.localized(area.title)))
					.font(.system(size: 15, weight: .bold))
					.foregroundStyle(theme.primaryText)
				  Spacer()
				  subtopicBadge(for: area)
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
		  title: isEditing ? LocalizationSupport.localized("Save Changes") : LocalizationSupport.localized("Continue to Onboarding"),
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
	.onboardingBackHandling(isActive: !isEditing)
	.navigationTitle(LocalizationSupport.localized("What can you teach?"))
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
		ToolbarItem(placement: .topBarLeading) {
		  Button(LocalizationSupport.localized("Cancel")) { dismiss() }
		}
	  }
	}
	.overlay {
	  if viewModel.isCheckingCompletion {
		ZStack {
		  theme.scrim.opacity(0.25).ignoresSafeArea()
		  VStack(spacing: 12) {
			ProgressView().progressViewStyle(.circular).scaleEffect(1.6).tint(theme.primaryText)
			Text(LocalizationSupport.localized("Checking your subjects…"))
			  .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.primaryText)
		  }
		}
	  }
	}
  }
  
  @ViewBuilder
  func subtopicBadge(for area: TeachingSubjectArea) -> some View {
	let count = viewModel.selectedSubtopicTitles(for: area).count
	let label = count == 0
	? LocalizationSupport.localized("Required")
	: String(format: LocalizationSupport.localized("selected"), count)
	Text(label)
	  .font(.system(size: 11, weight: .semibold))
	  .foregroundStyle(theme.secondaryText)
	  .padding(.horizontal, 10)
	  .frame(height: 24)
	  .background(theme.controlBorder.opacity(0.7))
	  .clipShape(Capsule())
  }
  
  var searchField: some View {
	HStack(spacing: 10) {
	  PlatformIcon(
		systemName: "magnifyingglass",
		size: 14,
		color: theme.secondaryText
	  )
	  
	  TextField(LocalizationSupport.localized("Search subjects or subtopics"), text: $viewModel.searchText)
		.font(.system(size: 13))
		.foregroundStyle(theme.primaryText)
		.textInputAutocapitalization(.never)
		.autocorrectionDisabled()
	}
	.padding(.horizontal, 16)
	.frame(height: 44)
	.background(theme.cardBackground)
	.clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
	.overlay {
	  RoundedRectangle(cornerRadius: 13, style: .continuous)
		.stroke(theme.controlBorder, lineWidth: 1)
	}
	.shadow(color: theme.cardShadow.opacity(0.03), radius: 10, x: 0, y: 4)
  }
}

@MainActor
struct SubjectAreaChip: View {
  let area: TeachingSubjectArea
  let isSelected: Bool
  let action: @MainActor () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
	Button(action: action) {
	  HStack(spacing: 7) {
		PlatformIcon(systemName: area.systemImage, size: 12, color: isSelected ? theme.onAccentText : theme.primaryText)
		Text(LocalizationSupport.localized(area.title))
		  .font(.system(size: 13, weight: .medium))
	  }
	  .foregroundStyle(isSelected ? theme.onAccentText : theme.primaryText)
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
