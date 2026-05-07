//
//  MainTabBar.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct MainTabBar: View {
    @Binding var selectedTab: MainTab

    var showLessonsBadge: Bool
    var showSettingsBadge: Bool

    var body: some View {
        HStack {
            tabButton(.home, showBadge: false)
            Spacer()
            tabButton(.lessons, showBadge: showLessonsBadge)
            Spacer()
            tabButton(.profile, showBadge: false)
            Spacer()
            tabButton(.settings, showBadge: showSettingsBadge)
        }
        .padding(.horizontal, 36)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background {
            Rectangle()
                .fill(.white)
                .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: -6)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    func tabButton(_ tab: MainTab, showBadge: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(selectedTab == tab ? Color.appPinkSoft : Color.clear)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(selectedTab == tab ? Color.appPink : Color.appSecondaryText)
                    }

                if showBadge {
                    Circle()
                        .fill(Color.appPink)
                        .frame(width: 8, height: 8)
                        .offset(x: -8, y: 5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(tab.title))
    }
}
