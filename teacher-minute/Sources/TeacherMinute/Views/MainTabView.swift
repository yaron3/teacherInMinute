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
        ZStack(alignment: .bottom) {
            Group {
                switch viewModel.selectedTab {
                case .home:
                    if viewModel.userMode == .student {
                        StudentHomeView(hidesTabBar: $hidesTabBar)
                    } else {
                        if let teacherDashboardViewModel {
                            TeacherDashboardView(
                                viewModel: teacherDashboardViewModel,
                                hidesTabBar: $hidesTabBar,
                                showsSessionOverlay: false,
                                showsIncomingOverlay: false
                            )
                        }
                    }

                case .lessons:
                    if viewModel.userMode == .student {
                        StudentLessonHistoryView()
                    } else {
                        TeacherLessonHistoryView()
                    }

                case .profile:
                    ProfileView()

                case .settings:
                    SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, hidesTabBar ? 0 : 82)

            if !hidesTabBar {
                MainTabBar(
                    selectedTab: $viewModel.selectedTab,
                    showLessonsBadge: viewModel.shouldShowLessonsBadge,
                    showSettingsBadge: viewModel.hasNotificationBadge
                )
            }

            teacherGlobalOverlay
        }
        .onChange(of: viewModel.selectedTab) { _, _ in
            if !isTeacherGlobalOverlayVisible {
                hidesTabBar = false
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    var teacherGlobalOverlay: some View {
        if viewModel.userMode == .teacher, let teacherDashboardViewModel {
            if let questionId = teacherDashboardViewModel.activeQuestionId {
                ChatSessionView(questionId: questionId, role: "teacher", title: "Student") {
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
        return teacherDashboardViewModel.activeQuestionId != nil || teacherDashboardViewModel.inviteIDs.first != nil
    }
}

#if os(iOS)
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
#endif
