//
//  NotificationPreferencesSettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct NotificationPreferencesSettingsView: View {
    let viewModel: any SettingsViewModeling
    @AppStorage("notifyIncomingTeacherMessage") var notifyIncomingTeacherMessage = true
    @AppStorage("notifyGeneralAnnouncements") var notifyGeneralAnnouncements = true
    @State var notificationState: PermissionState = .notDetermined
    @State var isRequesting = false

    var body: some View {
        Form {
            Section(header: Text(viewModel.systemPermissionSectionTitle)) {
                HStack {
                    Text(viewModel.pushNotificationsLabel)
                    Spacer()
                    Text(notificationState.subtitle)
                        .foregroundStyle(.secondary)
                }
                actionButton
            }

            Section(header: Text(viewModel.notificationsSectionTitle)) {
                Toggle(viewModel.incomingMessageNotificationLabel, isOn: $notifyIncomingTeacherMessage)
                    .disabled(!notificationState.isGranted)
                Toggle(viewModel.generalAnnouncementsNotificationLabel, isOn: $notifyGeneralAnnouncements)
                    .disabled(!notificationState.isGranted)
            }
        }
        .task {
            notificationState = await PermissionService.shared.notificationStatus()
            if notificationState == .notDetermined {
                await requestNotifications()
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch notificationState {
        case .notDetermined:
            Button {
                Task { await requestNotifications() }
            } label: {
                HStack {
                    Text(viewModel.enableNotificationsLabel)
                    Spacer()
                    if isRequesting {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(isRequesting)
        case .denied:
            Button(viewModel.openSystemSettingsLabel) {
                PermissionService.shared.openAppSettings()
            }
        case .granted:
            EmptyView()
        }
    }

    private func requestNotifications() async {
        isRequesting = true
        defer { isRequesting = false }
        let result = await PermissionService.shared.requestNotifications()
        notificationState = result
    }
}
