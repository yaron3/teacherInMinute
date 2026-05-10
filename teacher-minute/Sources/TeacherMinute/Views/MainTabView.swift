//
//  MainTabView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct MainTabView: View {
    @State var viewModel: MainTabViewModel
    
    init(userMode: AppUserMode = .teacher) {
        self._viewModel = State(wrappedValue: MainTabViewModel(userMode: userMode))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch viewModel.selectedTab {
                case .home:
                    if viewModel.userMode == .student {
                        StudentHomeView()
                    } else {
                        TeacherDashboardView()
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
            .padding(.bottom, 82)

            MainTabBar(
                selectedTab: $viewModel.selectedTab,
                showLessonsBadge: viewModel.shouldShowLessonsBadge,
                showSettingsBadge: viewModel.hasNotificationBadge
            )
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(Color(.systemBackground))
        .navigationBarBackButtonHidden(true)
    }
}

#if os(iOS)
struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
#endif
