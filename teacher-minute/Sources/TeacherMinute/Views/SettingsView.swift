//
//  SettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//


import SwiftUI

struct SettingsView: View {
    @State var viewModel = SettingsViewModel()
    @Environment(\.appRouter) var router

    var body: some View {
        ZStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Settings")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Color.appPrimaryText)
                        .padding(.top, 24)

                    VStack(spacing: 28) {
                        ForEach(viewModel.sections) { section in
                            settingsSection(section)
                        }
                    }
                    .padding(.top, 28)

                    Text(viewModel.appVersion)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.appSecondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 28)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 18)
            }
            
            if viewModel.isLoading {
                Color.black.opacity(0.18).ignoresSafeArea()
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(.white)
            }
        }
        .background(Color(.systemBackground))
        .sheet(item: $viewModel.activeSheet) { sheet in
            switch sheet {
            case .about(let url):
                AboutWebView(url: url)
            }
        }
        .alert("Delete Account", isPresented: $viewModel.showDeleteAccountConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task {
                    if await viewModel.deleteAccount() {
                        router.popToRoot()
                    }
                }
            }
        } message: {
            Text("This permanently deletes your account and profile data. This cannot be undone.")
        }
        .alert(viewModel.alertTitle, isPresented: $viewModel.showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }

    func settingsSection(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.title)
                .font(.system(size: 12, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.appSecondaryText)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                    SettingsRowView(row: row) {
                        select(row)
                    }

                    if index < section.rows.count - 1 {
                        Divider()
                            .padding(.leading, 58)
                    }
                }
            }
            .padding(.vertical, 8)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: .black.opacity(0.035), radius: 18, x: 0, y: 10)
        }
    }
    
    private func select(_ row: SettingsRow) {
        if row.action == .logOut {
            if viewModel.logOut() {
                router.popToRoot()
            }
            return
        }
        
        viewModel.select(row)
    }
}

struct SettingsRowView: View {
    let row: SettingsRow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Circle()
                    .fill(row.iconColor.backgroundColor)
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: row.systemImage)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(row.iconColor.foregroundColor)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(row.isDestructive ? .red : Color.appPrimaryText)

                    if let subtitle = row.subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.appSecondaryText)
            }
            .padding(.horizontal, 16)
            .frame(height: row.subtitle == nil ? 54 : 64)
        }
        .buttonStyle(.plain)
    }
}
