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
  
  var body: some View {
	VStack(alignment: .leading, spacing: 0) {
	  AuthIconHeader(systemImage: "person.3.fill")
		.padding(.top, 40)
	  
	  Text("Choose Your Role")
		.font(.system(size: 29, weight: .bold))
		.foregroundStyle(Color.authPrimaryText)
		.padding(.top, 24)
	  
	  Text("How do you want to use Math Connect? You\ncan change this later in settings.")
		.font(.system(size: 15))
		.foregroundStyle(Color.authSecondaryText)
		.lineSpacing(5)
		.padding(.top, 8)
	  
	  VStack(spacing: 22) {
		RoleCard(
		  title: "I am a Student",
		  icon: "graduationcap.fill",
		  details: ["On-demand help", "Per-minute billing"],
		  isSelected: viewModel.selectedRole == .student,
		  accent: .authPink
		) {
		  viewModel.selectedRole = .student
		}
		
		RoleCard(
		  title: "I am a Teacher",
		  icon: "person.crop.rectangle",
		  details: ["Earn while teaching", "Verification required"],
		  isSelected: viewModel.selectedRole == .teacher,
		  accent: .authPurple
		) {
		  viewModel.selectedRole = .teacher
		}
	  }
	  .padding(.top, 34)
	  
	  Spacer()
	  
	  AuthPrimaryButton(title: "Continue") {
		if viewModel.selectedRole == .teacher {
		  router.push(.teacherIdentityVerification)
		} else {
		  router.push(.completeProfile(role: viewModel.selectedRole))
		}
	  }
	  
	  Text("By continuing, you agree to our ")
		.font(.system(size: 12))
		.foregroundStyle(Color.authSecondaryText)
		.frame(maxWidth: .infinity)
		.overlay(alignment: .trailing) {
		  HStack(spacing: 2) {
			Text("Terms").underline()
			Text("&")
			Text("Privacy.").underline()
		  }
		  .font(.system(size: 12, weight: .semibold))
		  .foregroundStyle(Color.authPrimaryText)
		  .padding(.trailing, 10)
		}
		.padding(.top, 14)
		.padding(.bottom, 24)
	}
	.padding(.horizontal, 20)
	.background(Color(.systemBackground))
	.navigationBarTitleDisplayMode(.inline)
  }
}

struct RoleCard: View {
  let title: String
  let icon: String
  let details: [String]
  let isSelected: Bool
  let accent: Color
  let action: () -> Void
  
  var body: some View {
	Button(action: action) {
	  VStack(alignment: .leading, spacing: 18) {
		HStack {
		  RoundedRectangle(cornerRadius: 14, style: .continuous)
			.fill(accent.opacity(0.08))
			.frame(width: 46, height: 46)
			.overlay {
			  Image(systemName: icon)
				.font(.system(size: 21, weight: .semibold))
				.foregroundStyle(accent)
			}
		  
		  Spacer()
		  
		  if isSelected {
			Circle()
			  .fill(accent)
			  .frame(width: 22, height: 22)
			  .overlay {
				Image(systemName: "checkmark")
				  .font(.system(size: 10, weight: .bold))
				  .foregroundStyle(.white)
			  }
		  }
		}
		
		VStack(alignment: .leading, spacing: 8) {
		  Text(title)
			.font(.system(size: 18, weight: .bold))
			.foregroundStyle(Color.authPrimaryText)
		  
		  HStack(spacing: 8) {
			ForEach(details, id: \.self) { detail in
			  HStack(spacing: 4) {
				Circle()
				  .fill(accent)
				  .frame(width: 4, height: 4)
				
				Text(detail)
				  .font(.system(size: 12))
				  .foregroundStyle(Color.authSecondaryText)
			  }
			}
		  }
		}
	  }
	  .padding(20)
	  .frame(maxWidth: .infinity)
	  .background(.white)
	  .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
	  .overlay {
		RoundedRectangle(cornerRadius: 22, style: .continuous)
		  .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
	  }
	  .shadow(color: .black.opacity(0.035), radius: 20, x: 0, y: 12)
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
