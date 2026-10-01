//
//  TeacherSubjectsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//
//  What a teacher teaches: a step of onboarding, and the sheet that edits it
//  later from the dashboard or the profile. Both on the brand's ground.
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
    // A plain stack around the page, which carries its modifiers; see
    // `BrandTabScreen`.
    ZStack {
      if isEditing {
        BrandSheet(title: viewModel.navigationTitle(isEditing: true), closeLabel: viewModel.cancelLabel) {
          dismiss()
        } content: {
          content
        }
      } else {
        BrandSubpage(
          label: viewModel.stepIndicatorText,
          title: viewModel.navigationTitle(isEditing: false),
          backLabel: viewModel.onboardingBackLabel,
          onBack: { OnboardingBackCoordinator.shared.handleBack() }
        ) {
          content
        }
      }

      if viewModel.isCheckingCompletion {
        ZStack {
          theme.brandScrim.opacity(0.4).ignoresSafeArea()
          VStack(spacing: 12) {
            ProgressView()
              .progressViewStyle(.circular)
              .scaleEffect(1.6)
              .tint(theme.onDarkFill)
            Text(viewModel.checkingText)
              .font(.system(size: 14, weight: .medium))
              .foregroundStyle(theme.onDarkFill)
          }
        }
      }
    }
    .environment(\.colorScheme, .dark)
    .onboardingBackHandling(viewModel: viewModel, isActive: !isEditing)
    .toolbar(.hidden, for: .navigationBar)
    .onAppear {
      if isEditing {
        viewModel.onContinue = { dismiss() }
        viewModel.loadSelections()
      } else {
        viewModel.onContinue = { router.push(.completeProfile(role: .teacher)) }
        viewModel.checkAndAutoAdvance()
      }
    }
  }

  // Split out of `body`, which the type checker would otherwise have to solve
  // in one piece.
  @ViewBuilder
  var content: some View {
    if !isEditing {
      BrandPageHero(title: viewModel.onboardingTitle)
    }

    Text(viewModel.introText)
      .font(.system(size: 15))
      .foregroundStyle(theme.brandSecondaryText)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)

    FlatSearchField(placeholder: viewModel.searchPlaceholder, text: $viewModel.searchText)

    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(viewModel.subjectAreaSectionTitle)
          .font(.system(size: 17, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
        Spacer()
        countBadge(viewModel.selectedCountText)
      }

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
    }
    .brandCard()

    if viewModel.shouldShowSubtopicsPrompt {
      Text(viewModel.noAreasSelectedText)
        .font(.system(size: 14))
        .foregroundStyle(theme.brandSecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      ForEach(viewModel.selectedAreas) { area in
        VStack(alignment: .leading, spacing: 14) {
          HStack {
            Text(viewModel.subtopicsSectionTitle(for: area))
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(theme.onDarkFill)
            Spacer()
            countBadge(viewModel.subtopicBadgeLabel(for: area))
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
        .brandCard()
      }
    }

    AuthPrimaryButton(
      title: viewModel.continueButtonLabel(isEditing: isEditing),
      isEnabled: viewModel.canContinue
    ) {
      viewModel.continueOnboarding()
    }
    .padding(.top, 8)
  }

  func countBadge(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 12, weight: .semibold))
      .foregroundStyle(theme.brandSecondaryText)
      .padding(.horizontal, 10)
      .frame(height: 24)
      .overlay {
        Capsule()
          .stroke(theme.brandControlBorder, lineWidth: 1)
      }
  }
}

/// A subject area to teach in: outlined, or filled cyan when chosen.
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
        PlatformIcon(
          systemName: area.systemImage,
          size: 12,
          color: isSelected ? theme.onBrandAction : theme.brandActionBackground
        )
        Text(title)
          .font(.system(size: 14, weight: .medium))
      }
      .foregroundStyle(isSelected ? theme.onBrandAction : theme.onDarkFill)
      .padding(.horizontal, 14)
      .frame(height: 36)
      .background(isSelected ? theme.brandActionBackground : theme.brandCardSurface)
      .clipShape(Capsule())
      .overlay {
        Capsule()
          .stroke(isSelected ? theme.brandActionBackground : theme.brandControlBorder, lineWidth: 1)
      }
    }
    .buttonStyle(.plain)
  }
}
