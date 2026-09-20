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
		  Text(viewModel.stepIndicatorText)
			.font(.system(size: 13, weight: .medium))
			.foregroundStyle(theme.secondaryText)
			.frame(maxWidth: .infinity)
		}
		
		
		Text(viewModel.introText)
		  .font(.system(size: 13))
		  .foregroundStyle(theme.secondaryText)
		  .lineSpacing(5)
		  .padding(.top, 8)
		
		searchField
		  .padding(.top, 24)
		
		HStack {
		  Text(viewModel.subjectAreaSectionTitle)
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
			  title: viewModel.areaTitle(area),
			  isSelected: viewModel.isAreaSelected(area)
			) {
			  viewModel.toggleArea(area)
			}
		  }
		}
		.padding(.top, 16)
		
		if viewModel.shouldShowSubtopicsPrompt {
		  Text(viewModel.noAreasSelectedText)
			.font(.system(size: 13))
			.foregroundStyle(theme.secondaryText)
			.padding(.top, 24)
		} else {
		  VStack(alignment: .leading, spacing: 22) {
			ForEach(viewModel.selectedAreas) { area in
			  VStack(alignment: .leading, spacing: 12) {
				HStack {
				  Text(viewModel.subtopicsSectionTitle(for: area))
					.font(.system(size: 15, weight: .bold))
					.foregroundStyle(theme.primaryText)
				  Spacer()
				  subtopicBadge(for: area)
				}
				
				FlowLayout(spacing: 10) {
				  ForEach(viewModel.visibleSubtopics(for: area)) { subtopic in
					SubjectChip(
					  subject: subtopic,
					  title: viewModel.subtopicTitle(subtopic),
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
		  title: viewModel.continueButtonLabel(isEditing: isEditing),
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
	.onboardingBackHandling(viewModel: viewModel, isActive: !isEditing)
	.navigationTitle(viewModel.onboardingTitle)
	.onAppear {
	  if isEditing {
		viewModel.onContinue = { dismiss() }
		viewModel.loadSelections()
	  } else {
		viewModel.onContinue = { router.push(.completeProfile(role: .teacher)) }
		viewModel.checkAndAutoAdvance()
	  }
	}
	.navigationTitle(viewModel.navigationTitle(isEditing: isEditing))
	.toolbar {
	  if isEditing {
		ToolbarItem(placement: .topBarLeading) {
		  Button(viewModel.cancelLabel) { dismiss() }
		}
	  }
	}
	.overlay {
	  if viewModel.isCheckingCompletion {
		ZStack {
		  theme.scrim.opacity(0.25).ignoresSafeArea()
		  VStack(spacing: 12) {
			ProgressView().progressViewStyle(.circular).scaleEffect(1.6).tint(theme.primaryText)
			Text(viewModel.checkingText)
			  .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.primaryText)
		  }
		}
	  }
	}
  }
  
  @ViewBuilder
  func subtopicBadge(for area: TeachingSubjectArea) -> some View {
	Text(viewModel.subtopicBadgeLabel(for: area))
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
	  
	  TextField(viewModel.searchPlaceholder, text: $viewModel.searchText)
		.textFieldStyle(.plain)
		.font(.system(size: 13))
		.foregroundStyle(theme.primaryText)
		.textInputAutocapitalization(.never)
		.autocorrectionDisabled()
	}
	.padding(.horizontal, 16)
	.frame(height: textFieldContainerHeight(44))
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
  let title: String
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
		Text(title)
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
