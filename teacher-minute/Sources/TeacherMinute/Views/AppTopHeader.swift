//
//  AppTopHeader.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct AppTopHeader: View {
    let avatarSystemImage: String
    let eyebrow: String
    let name: String
    var showNotificationBadge = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color.appPurpleSoft)
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: avatarSystemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.appPurple)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(eyebrow)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appSecondaryText)

                Text(name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.appPrimaryText)
            }

            Spacer()

            Button {
                // TODO: open notifications
            } label: {
                ZStack(alignment: .topTrailing) {
                    Circle()
                        .fill(.white)
                        .frame(width: 42, height: 42)
                        .shadow(color: .black.opacity(0.05), radius: 12, x: 0, y: 6)
                        .overlay {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Color.appPrimaryText)
                        }

                    if showNotificationBadge {
                        Circle()
                            .fill(Color.appPink)
                            .frame(width: 8, height: 8)
                            .offset(x: -8, y: 8)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }
}

struct RoundedInfoCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(18)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: 18, x: 0, y: 10)
    }
}

struct SmallPill: View {
    let title: String
    var foreground: Color = .appPink
    var background: Color = .appPinkSoft

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(background)
            .clipShape(Capsule())
    }
}