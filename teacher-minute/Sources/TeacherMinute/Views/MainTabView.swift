//
//  MainTabView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct MainTabView: View {
    @State var viewModel: MainTabViewModel
    @State var teacherDashboardViewModel: TeacherDashboardViewModel?
    @State var hidesTabBar = false
    
    init(userMode: AppUserMode = .teacher) {
        self._viewModel = State(wrappedValue: MainTabViewModel(userMode: userMode))
        self._teacherDashboardViewModel = State(wrappedValue: userMode == .teacher ? TeacherDashboardViewModel() : nil)
    }

    var body: some View {
        ZStack {
            TabView(selection: $viewModel.selectedTab) {
                tabContent(.home)
                    .tabItem {
                        Label("Home", systemImage: MainTab.home.systemImage)
                    }
                    .tag(MainTab.home)

                tabContent(.lessons)
                    .tabItem {
                        Label {
                            Text("Lessons")
                        } icon: {
                            Image(MainTab.lessons.systemImage, bundle: .module)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 40, height: 40)
                        }
                    }
                    .tag(MainTab.lessons)
                    .badge(viewModel.shouldShowLessonsBadge ? 1 : 0)

                tabContent(.profile)
                    .tabItem {
                        Label("Profile", systemImage: MainTab.profile.systemImage)
                    }
                    .tag(MainTab.profile)

                tabContent(.settings)
                    .tabItem {
                        Label("Settings", systemImage: MainTab.settings.systemImage)
                    }
                    .tag(MainTab.settings)
            }
            .toolbar(hidesTabBar ? .hidden : .visible, for: .tabBar)

            teacherGlobalOverlay
        }
        .onChange(of: viewModel.selectedTab) { _, _ in
            if !isTeacherGlobalOverlayVisible {
                hidesTabBar = false
            }
        }
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
        .navigationBarHidden(true)
    }

    @ViewBuilder
    func tabContent(_ tab: MainTab) -> some View {
        switch tab {
        case .home:
            if viewModel.userMode == .student {
                StudentHomeView(hidesTabBar: $hidesTabBar)
            } else if let teacherDashboardViewModel {
                TeacherDashboardView(
                    viewModel: teacherDashboardViewModel,
                    hidesTabBar: $hidesTabBar,
                    showsSessionOverlay: false,
                    showsIncomingOverlay: false
                )
            }

        case .lessons:
            if viewModel.userMode == .student {
                StudentLessonHistoryView()
            } else {
                TeacherLessonHistoryView()
            }

        case .profile:
            ProfileView(viewModel: ProfileViewModel(roleType: viewModel.userMode == .teacher ? .teacher : .student))

        case .settings:
			SettingsView(role: viewModel.userMode, viewModel: nil)
        }
    }

    @ViewBuilder
    var teacherGlobalOverlay: some View {
        if viewModel.userMode == .teacher, let teacherDashboardViewModel {
            if teacherDashboardViewModel.isAcceptingCalls, teacherDashboardViewModel.acceptingQuestionId != nil {
                ConnectionSetupView(
                    participantName: teacherDashboardViewModel.activeStudentName,
                    hasAudio: false,
                    footerText: "Setting up the session"
                ) {
                    teacherDashboardViewModel.cancelAcceptingInvite()
                }
                .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                .zIndex(20)
                .onAppear {
                    hidesTabBar = true
                }
                .onDisappear {
                    hidesTabBar = false
                }
            } else if let questionId = teacherDashboardViewModel.activeQuestionId {
                ChatSessionView(
                    questionId: questionId,
                    role: "teacher",
                    title: "Student",
                    initialDetails: teacherDashboardViewModel.activeChatInitialDetails()
                ) {
                    teacherDashboardViewModel.endCall()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(20)
                .onAppear {
                    hidesTabBar = true
                }
                .onDisappear {
                    hidesTabBar = false
                }
            } else if let inviteID = teacherDashboardViewModel.inviteIDs.first {
                TeacherIncomingQuestionOverlay(inviteID: inviteID, viewModel: teacherDashboardViewModel)
                    .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                    .zIndex(20)
                    .onAppear {
                        hidesTabBar = true
                    }
                    .onDisappear {
                        hidesTabBar = false
                    }
            }
        }
    }

    var isTeacherGlobalOverlayVisible: Bool {
        guard viewModel.userMode == .teacher, let teacherDashboardViewModel else { return false }
        return teacherDashboardViewModel.isAcceptingCalls || teacherDashboardViewModel.activeQuestionId != nil || teacherDashboardViewModel.inviteIDs.first != nil
    }
}

#if os(iOS)
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
#endif
