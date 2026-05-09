//
//  TeacherDashboardView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct TeacherDashboardView: View {
  @State var viewModel = TeacherDashboardViewModel()
  
  var body: some View {
	ScrollView(.vertical, showsIndicators: false) {
	  VStack(alignment: .leading, spacing: 0) {
		AppTopHeader(
		  avatarSystemImage: "person.crop.circle.fill",
		  eyebrow: "Teacher Dashboard",
		  name: viewModel.teacherName,
		  showNotificationBadge: viewModel.isOnline
		)
		.padding(.top, 18)
		
		if viewModel.isOnline {
		  onlineHero
			.padding(.top, 34)
		  
		  liveEarningsCard
			.padding(.top, 24)
		  
		  onlineStatusCard
			.padding(.top, 20)
		  
		  liveQueue
			.padding(.top, 24)
		} else {
		  offlineHero
			.padding(.top, 44)
		  
		  teacherStatusCard
			.padding(.top, 38)
		  
		  earningsSnapshot
			.padding(.top, 26)
		  
		  readinessChecklist
			.padding(.top, 24)
		}
	  }
	  .padding(.horizontal, 18)
	  .padding(.bottom, 24)
	}
	.background(Color.white)
  }
  
  var offlineHero: some View {
	VStack(spacing: 0) {
	  Circle()
		.fill(Color.appGrayBackground)
		.frame(width: 84, height: 84)
		.overlay {
		  PlatformIcon(systemName: "moon.fill", size: 34, weight: .semibold, color: .appSecondaryText)
		}
	  
	  Text("You're Offline")
		.font(.system(size: 26, weight: .bold))
		.foregroundStyle(Color.appPrimaryText)
		.padding(.top, 22)
	  
	  Text("Go online to start receiving student requests and\nearn money.")
		.font(.system(size: 13))
		.foregroundStyle(Color.appSecondaryText)
		.multilineTextAlignment(.center)
		.lineSpacing(5)
		.padding(.top, 10)
	  
	  Button {
		viewModel.toggleOnline()
	  } label: {
		HStack(spacing: 10) {
		  Circle()
			.fill(.white)
			.frame(width: 44, height: 44)
		  
		  Text("OFF")
			.font(.system(size: 12, weight: .bold))
			.foregroundStyle(Color.appSecondaryText)
			.padding(.trailing, 14)
		}
		.frame(height: 48)
		.background(Color.appBorder)
		.clipShape(Capsule())
	  }
	  .buttonStyle(.plain)
	  .padding(.top, 26)
	}
	.frame(maxWidth: .infinity)
  }
  
  var onlineHero: some View {
	VStack(spacing: 0) {
	  Circle()
		.fill(Color.appGreenSoft)
		.frame(width: 112, height: 112)
		.overlay {
		  Circle()
			.fill(Color.appGreen)
			.frame(width: 64, height: 64)
			.overlay {
			  PlatformIcon(systemName: "antenna.radiowaves.left.and.right", size: 25, weight: .semibold, color: .white)
			}
		}
	  
	  Text("You're Online")
		.font(.system(size: 26, weight: .bold))
		.foregroundStyle(Color.appPrimaryText)
		.padding(.top, 18)
	  
	  HStack(spacing: 7) {
		Circle()
		  .fill(Color.appGreen)
		  .frame(width: 7, height: 7)
		
		Text("Waiting for students...")
		  .font(.system(size: 13, weight: .semibold))
		  .foregroundStyle(Color.appGreen)
	  }
	  .padding(.top, 10)
	  
	  Button {
		viewModel.toggleOnline()
	  } label: {
		HStack(spacing: 10) {
		  Text("ON")
			.font(.system(size: 12, weight: .bold))
			.foregroundStyle(.white)
			.padding(.leading, 16)
		  
		  Circle()
			.fill(.white)
			.frame(width: 44, height: 44)
		}
		.frame(height: 48)
		.background(Color.appGreen)
		.clipShape(Capsule())
	  }
	  .buttonStyle(.plain)
	  .padding(.top, 26)
	}
	.frame(maxWidth: .infinity)
  }
  
  var teacherStatusCard: some View {
	RoundedInfoCard {
	  HStack(spacing: 14) {
		Circle()
		  .fill(Color.appGreenSoft)
		  .frame(width: 38, height: 38)
		  .overlay {
			PlatformIcon(systemName: "checkmark.seal", size: 15, weight: .semibold, color: .appGreen)
		  }
		
		VStack(alignment: .leading, spacing: 4) {
		  Text("Verified Expert")
			.font(.system(size: 14, weight: .bold))
			.foregroundStyle(Color.appPrimaryText)
		  
		  Text("Calculus, Algebra II")
			.font(.system(size: 12))
			.foregroundStyle(Color.appSecondaryText)
		}
		
		Spacer()
		
		Button {
		  viewModel.editSubjects()
		} label: {
		  Text("Edit Subjects")
			.font(.system(size: 12, weight: .medium))
			.foregroundStyle(Color.appPink)
		}
		.buttonStyle(.plain)
	  }
	}
  }
  
  var earningsSnapshot: some View {
	VStack(alignment: .leading, spacing: 14) {
	  Text("Earnings Snapshot")
		.font(.system(size: 18, weight: .bold))
		.foregroundStyle(Color.appPrimaryText)
	  
	  HStack(spacing: 16) {
		EarningsCard(title: "Today", amount: "$0.00", subtitle: "0 mins tutored")
		  .frame(maxWidth: .infinity)
		EarningsCard(title: "This Week", amount: "$142.50", subtitle: "+12% vs last week", subtitleColor: .appGreen)
		  .frame(maxWidth: .infinity)
	  }
	}
  }
  
  var liveEarningsCard: some View {
	RoundedInfoCard {
	  HStack {
		VStack(alignment: .leading, spacing: 10) {
		  Text("Live Earnings Today")
			.font(.system(size: 12, weight: .medium))
			.foregroundStyle(Color.appSecondaryText)
		  
		  Text("$14.50")
			.font(.system(size: 25, weight: .bold))
			.foregroundStyle(Color.appPrimaryText)
		}
		
		Spacer()
		
		VStack(alignment: .trailing, spacing: 8) {
		  SmallPill(title: "⚡ $0.50/min", foreground: .appPink, background: .appPinkSoft)
		  
		  Text("29 mins tutored")
			.font(.system(size: 11))
			.foregroundStyle(Color.appSecondaryText)
		}
	  }
	}
	.background(Color.appPinkSoft.opacity(0.3))
  }
  
  var onlineStatusCard: some View {
	RoundedInfoCard {
	  HStack {
		statusItem(icon: "mic.fill", title: "Mic", subtitle: "On", color: .appGreen)
		Spacer()
		statusItem(icon: "video.fill", title: "Cam", subtitle: "Ready", color: .appGreen)
		Spacer()
		statusItem(icon: "circle.fill", title: "Excellent", subtitle: "Connection", color: .appGreen)
	  }
	}
  }
  
  var liveQueue: some View {
	VStack(alignment: .leading, spacing: 14) {
	  HStack {
		Text("Live Queue")
		  .font(.system(size: 18, weight: .bold))
		  .foregroundStyle(Color.appPrimaryText)
		
		Spacer()
		
		SmallPill(title: "2 Waiting", foreground: .appPrimaryText, background: .appGrayBackground)
	  }
	  
	  ForEach(viewModel.liveRequests) { request in
		LiveRequestCard(request: request) {
		  viewModel.accept(request)
		} reject: {
		  viewModel.reject(request)
		}
	  }
	}
  }
  
  var readinessChecklist: some View {
	VStack(alignment: .leading, spacing: 14) {
	  Text("Readiness Checklist")
		.font(.system(size: 16, weight: .bold))
		.foregroundStyle(Color.appPrimaryText)
	  
	  checklistRow(icon: "mic.fill", title: "Microphone Enabled", subtitle: "Required for voice sessions.", color: .appGreen)
	  checklistRow(icon: "camera.fill", title: "Camera Access (Optional)", subtitle: "Enable for video tutoring.", color: .appSecondaryText)
	  checklistRow(icon: "wifi", title: "Connection Test", subtitle: "Check your internet speed.", color: .appSecondaryText)
	}
	.padding(20)
	.background(Color.appGrayBackground)
	.clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }
  
  func statusItem(icon: String, title: String, subtitle: String, color: Color) -> some View {
	HStack(spacing: 6) {
	  PlatformIcon(systemName: icon, size: 13, weight: .semibold, color: color)
	  
	  VStack(alignment: .leading, spacing: 2) {
		Text(title)
		  .font(.system(size: 11, weight: .bold))
		  .foregroundStyle(Color.appPrimaryText)
		
		Text(subtitle)
		  .font(.system(size: 10))
		  .foregroundStyle(Color.appSecondaryText)
	  }
	}
  }
  
  func checklistRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
	HStack(spacing: 12) {
	  Circle()
		.fill(color.opacity(0.12))
		.frame(width: 30, height: 30)
		.overlay {
		  PlatformIcon(systemName: icon, size: 12, weight: .semibold, color: color)
		}
	  
	  VStack(alignment: .leading, spacing: 3) {
		Text(title)
		  .font(.system(size: 13, weight: .bold))
		  .foregroundStyle(Color.appPrimaryText)
		
		Text(subtitle)
		  .font(.system(size: 11))
		  .foregroundStyle(Color.appSecondaryText)
	  }
	  
	  Spacer()
	}
  }
  
  struct EarningsCard: View {
	let title: String
	let amount: String
	let subtitle: String
	var subtitleColor: Color = .appSecondaryText
	
	var body: some View {
	  RoundedInfoCard {
		VStack(alignment: .leading, spacing: 8) {
		  Text(title)
			.font(.system(size: 12))
			.foregroundStyle(Color.appSecondaryText)
		  
		  Text(amount)
			.font(.system(size: 25, weight: .bold))
			.foregroundStyle(Color.appPrimaryText)
		  
		  Text(subtitle)
			.font(.system(size: 11))
			.foregroundStyle(subtitleColor)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	  }
	}
  }
  
  struct LiveRequestCard: View {
	let request: LiveStudentRequest
	let accept: () -> Void
	let reject: () -> Void
	
	var body: some View {
	  RoundedInfoCard {
		VStack(spacing: 14) {
		  HStack(spacing: 12) {
			Circle()
			  .fill(Color.appPurpleSoft)
			  .frame(width: 48, height: 48)
			  .overlay {
				PlatformIcon(systemName: "person.crop.circle.fill", size: 28, color: .appPurple)
			  }
			
			VStack(alignment: .leading, spacing: 5) {
			  Text(request.studentName)
				.font(.system(size: 14, weight: .bold))
				.foregroundStyle(Color.appPrimaryText)
			  
			  Text(request.topic)
				.font(.system(size: 11))
				.foregroundStyle(Color.appSecondaryText)
			}
			
			Spacer()
			
			VStack(alignment: .trailing, spacing: 8) {
			  if request.isHighPriority {
				SmallPill(title: "High Priority", foreground: .appPink, background: .appPinkSoft)
			  }
			  
			  Text(request.waitingTime)
				.font(.system(size: 11))
				.foregroundStyle(Color.appSecondaryText)
			}
		  }
		  
		  HStack(spacing: 12) {
			Button(action: accept) {
			  Text(request.isHighPriority ? "Accept Request" : "Accept")
				.font(.system(size: 13, weight: .bold))
				.foregroundStyle(request.isHighPriority ? .white : Color.appPink)
				.frame(maxWidth: .infinity)
				.frame(height: 42)
				.background(request.isHighPriority ? Color.appPink : .white)
				.clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
				.overlay {
				  RoundedRectangle(cornerRadius: 9, style: .continuous)
					.stroke(Color.appPink, lineWidth: request.isHighPriority ? 0 : 1.5)
				}
			}
			.buttonStyle(.plain)
			
			if request.isHighPriority {
			  Button(action: reject) {
				PlatformIcon(systemName: "xmark", size: 13, weight: .bold, color: .appSecondaryText)
				  .frame(width: 48, height: 42)
				  .background(Color.appGrayBackground)
				  .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
			  }
			  .buttonStyle(.plain)
			}
		  }
		}
	  }
	  .overlay {
		RoundedRectangle(cornerRadius: 18, style: .continuous)
		  .stroke(request.isHighPriority ? Color.appPink : Color.clear, lineWidth: 1.5)
	  }
	}
  }
}
