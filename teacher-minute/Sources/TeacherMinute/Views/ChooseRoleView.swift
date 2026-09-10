//
//  ChooseRoleView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct ChooseRoleView: View {
  @State var viewModel = ChooseRoleViewModel()
  @Environment(\.appRouter) var router
  @State var showingTerms = false
  @State var showingPrivacy = false
  @State var termsURL: URL?
  @State var privacyURL: URL?
  @State var showLegalAlert = false
  @State var legalAlertMessage = ""
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    // The role cards and the teacher's "How it works" panel together outgrow a
    // short screen, and the panel is the part that explains what the teacher is
    // signing up for — so the content scrolls and Continue stays pinned below
    // it rather than being pushed off the bottom.
    VStack(alignment: .leading, spacing: 0) {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 0) {

      Text(viewModel.subtitleText)
        .font(.system(size: 15))
        .foregroundStyle(theme.secondaryText)
        .lineSpacing(5)
        .padding(.top, 8)

      VStack(spacing: 12) {
        RoleCard(
          title: viewModel.studentRoleTitle,
          icon: "graduationcap.fill",
          description: viewModel.studentDescriptionLines,
          details: viewModel.studentRoleBullets,
          isSelected: viewModel.selectedRole == .student,
          accent: theme.accent
        ) {
          viewModel.selectedRole = .student
        }

        RoleCard(
          title: viewModel.teacherRoleTitle,
          icon: "person.crop.rectangle",
          description: viewModel.teacherDescriptionLines,
          details: viewModel.teacherRoleBullets,
          isSelected: viewModel.selectedRole == .teacher,
          accent: theme.accent
        ) {
          viewModel.selectedRole = .teacher
        }
      }
      .padding(.top, 34)
	  if viewModel.selectedRole == .teacher {
		  HowItWorksPanel(
			title: viewModel.howItWorksTeacherTitle,
			steps: [
			  HowItWorksStep(number: 1, title: viewModel.howItWorksTeacherStep1Title, subtitle: viewModel.howItWorksStep1Subtitle, tint: theme.info),
			  HowItWorksStep(number: 2, title: viewModel.connectTeacherStepTitle, subtitle: viewModel.howItWorksStep2Subtitle, tint: theme.warning),
			  HowItWorksStep(number: 3, title: viewModel.howItWorksTeacherStep3Title, subtitle: viewModel.howItWorksStep3Subtitle, tint: theme.penGreen),

			],
			theme: theme
		  )
		  .padding(.top,12)
		
	  }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 20)
      }

      AuthPrimaryButton(title: viewModel.continueLabel) {
        Task { @MainActor in
          continueWithSelectedRole()
        }
      }

//      HStack(spacing: 2) {
//        Text(LocalizationSupport.localized("By continuing, you agree to our"))
//          .foregroundStyle(theme.secondaryText)
//        Button { openTerms() } label: {
//          Text(LocalizationSupport.localized("Terms")).underline()
//            .fontWeight(.semibold)
//            .foregroundStyle(theme.primaryText)
//        }
//        .buttonStyle(.plain)
//        Text(LocalizationSupport.localized("&"))
//          .foregroundStyle(theme.secondaryText)
//        Button { openPrivacy() } label: {
//          Text(LocalizationSupport.localized("Privacy.")).underline()
//            .fontWeight(.semibold)
//            .foregroundStyle(theme.primaryText)
//        }
//        .buttonStyle(.plain)
//      }
//      .font(.system(size: 12))
//      .frame(maxWidth: .infinity)
//      .padding(.top, 14)
//      .padding(.bottom, 24)
    }
    .padding(.horizontal, 20)
    .background(theme.screenBackground)
    .navigationBarTitleDisplayMode(.inline)
    .onboardingBackHandling(viewModel: viewModel)
    .sheet(isPresented: $showingTerms) {
      if let termsURL {
        NavigationStack { AboutWebView(url: termsURL, title: viewModel.eulaTitle) }
      }
    }
	.navigationTitle(viewModel.screenTitle)
    .sheet(isPresented: $showingPrivacy) {
      if let privacyURL {
        NavigationStack { AboutWebView(url: privacyURL, title: viewModel.privacyPolicyTitle) }
      }
    }
    .appDialog(
      viewModel.screenTitle,
      isPresented: $showLegalAlert,
      message: legalAlertMessage,
      actions: [AppDialogAction(viewModel.okLabel)]
    )
  }

  private func continueWithSelectedRole() {
    if viewModel.selectedRole == .teacher {
      router.push(.teacherIdentityVerification)
    } else {
      router.push(.completeProfile(role: viewModel.selectedRole))
    }
  }

  private func openTerms() {
    termsURL = URL(string: RemoteConfigService.getLocalizedString(for: .eulaURL))
    if termsURL != nil {
      showingTerms = true
      return
    }

    legalAlertMessage = SettingsError.missingLegalURL("EULA").localizedDescription
    showLegalAlert = true
  }

  private func openPrivacy() {
    privacyURL = URL(string: RemoteConfigService.getLocalizedString(for: .privacyPolicyURL))
    if privacyURL != nil {
      showingPrivacy = true
      return
    }

    legalAlertMessage = SettingsError.missingLegalURL(viewModel.privacyPolicyTitle).localizedDescription
    showLegalAlert = true
  }
}

struct RoleCard: View {
  let title: String
  let icon: String
  let description: [String]
  let details: [String]
  let isSelected: Bool
  let accent: Color
  let action: () -> Void
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
            .fill(accent.opacity(0.08))
            .frame(width: 46, height: 46)
            .overlay {
              PlatformIcon(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(accent)
            }
		  VStack {
			ForEach (description, id: \.self) { detail in
			  Text(detail)
				.font(.system(size: 14, weight: .semibold))
				.foregroundStyle(theme.primaryText)
			}
		  }
          Spacer()

          if isSelected {
            Circle()
              .fill(accent)
              .frame(width: 22, height: 22)
              .overlay {
                PlatformIcon(
                  systemName: "checkmark",
                  size: 10,
                  weight: .bold,
                  color: theme.primaryText
                )
              }
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(theme.primaryText)

          HStack(spacing: 8) {
            ForEach(details, id: \.self) { detail in
              HStack(spacing: 4) {
                Circle()
                  .fill(accent)
                  .frame(width: 4, height: 4)

                Text(detail)
                  .font(.system(size: 12))
                  .foregroundStyle(theme.secondaryText)
              }
            }
          }
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity)
      .background(theme.cardBackground)
      .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: flatRadius, style: .continuous)
          .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
      }
    }
    .buttonStyle(.plain)
  }
}

#if os(iOS)
struct RoleCardScreen_Previews: PreviewProvider {
  static var previews: some View {
    ChooseRoleView()
  }
}
#endif
