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
    VStack(alignment: .leading, spacing: 0) {
      AuthIconHeader(systemImage: "person.3.fill")
        .padding(.top, 40)

      Text(LocalizationSupport.localized("Choose Your Role"))
        .font(.system(size: 29, weight: .bold))
        .foregroundStyle(theme.authPrimaryText)
        .padding(.top, 24)

      Text(LocalizationSupport.localized("How do you want to use Math Connect? You\ncan change this later in settings."))
        .font(.system(size: 15))
        .foregroundStyle(theme.authSecondaryText)
        .lineSpacing(5)
        .padding(.top, 8)

      VStack(spacing: 22) {
        RoleCard(
          title: LocalizationSupport.localized("I am a Student"),
          icon: "graduationcap.fill",
          details: [
            LocalizationSupport.localized("On-demand help"),
            LocalizationSupport.localized("Per-minute billing")
          ],
          isSelected: viewModel.selectedRole == .student,
          accent: theme.authPink
        ) {
          viewModel.selectedRole = .student
        }

        RoleCard(
          title: LocalizationSupport.localized("I am a Teacher"),
          icon: "person.crop.rectangle",
          details: [
            LocalizationSupport.localized("Earn while teaching"),
            LocalizationSupport.localized("Verification required")
          ],
          isSelected: viewModel.selectedRole == .teacher,
          accent: theme.authPurple
        ) {
          viewModel.selectedRole = .teacher
        }
      }
      .padding(.top, 34)

      Spacer()

      AuthPrimaryButton(title: LocalizationSupport.localized("Continue")) {
        Task { @MainActor in
          continueWithSelectedRole()
        }
      }

//      HStack(spacing: 2) {
//        Text(LocalizationSupport.localized("By continuing, you agree to our"))
//          .foregroundStyle(theme.authSecondaryText)
//        Button { openTerms() } label: {
//          Text(LocalizationSupport.localized("Terms")).underline()
//            .fontWeight(.semibold)
//            .foregroundStyle(theme.authPrimaryText)
//        }
//        .buttonStyle(.plain)
//        Text(LocalizationSupport.localized("&"))
//          .foregroundStyle(theme.authSecondaryText)
//        Button { openPrivacy() } label: {
//          Text(LocalizationSupport.localized("Privacy.")).underline()
//            .fontWeight(.semibold)
//            .foregroundStyle(theme.authPrimaryText)
//        }
//        .buttonStyle(.plain)
//      }
//      .font(.system(size: 12))
//      .frame(maxWidth: .infinity)
//      .padding(.top, 14)
//      .padding(.bottom, 24)
    }
    .padding(.horizontal, 20)
    .background(Color(.systemBackground))
    .navigationBarTitleDisplayMode(.inline)
    .sheet(isPresented: $showingTerms) {
      if let termsURL {
        NavigationStack { AboutWebView(url: termsURL, title: LocalizationSupport.localized("EULA")) }
      }
    }
    .sheet(isPresented: $showingPrivacy) {
      if let privacyURL {
        NavigationStack { AboutWebView(url: privacyURL, title: LocalizationSupport.localized("Privacy Policy")) }
      }
    }
    .alert(LocalizationSupport.localized("Choose Your Role"), isPresented: $showLegalAlert) {
      Button(LocalizationSupport.localized("OK"), role: .cancel) {}
    } message: {
      Text(legalAlertMessage)
    }
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

    legalAlertMessage = SettingsError.missingLegalURL(LocalizationSupport.localized("Privacy Policy")).localizedDescription
    showLegalAlert = true
  }
}

struct RoleCard: View {
  let title: String
  let icon: String
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
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(accent.opacity(0.08))
            .frame(width: 46, height: 46)
            .overlay {
              PlatformIcon(systemName: icon)
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(accent)
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
                  color: theme.appPrimaryText
                )
              }
          }
        }

        VStack(alignment: .leading, spacing: 8) {
          Text(title)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(theme.authPrimaryText)

          HStack(spacing: 8) {
            ForEach(details, id: \.self) { detail in
              HStack(spacing: 4) {
                Circle()
                  .fill(accent)
                  .frame(width: 4, height: 4)

                Text(detail)
                  .font(.system(size: 12))
                  .foregroundStyle(theme.authSecondaryText)
              }
            }
          }
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity)
      .background(theme.appCardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
          .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
      }
      .shadow(color: theme.appPrimaryText.opacity(0.035), radius: 20, x: 0, y: 12)
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
