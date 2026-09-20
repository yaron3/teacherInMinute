//
//  MediaPermissionsSettingsView.swift
//  teacher-minute
//
//  The capture permissions a lesson needs, in one place. The teacher
//  dashboard's readiness rows ask for the same two, but a student never sees
//  that screen, and neither role can review what it has already granted
//  without leaving the app.
//
//  Notifications are deliberately not here: they have their own screen under
//  Notification Preferences, which also carries the per-kind toggles.
//

import SwiftUI

struct MediaPermissionsSettingsView: View {
    let viewModel: any SettingsViewModeling
    @State var micState: PermissionState = .notDetermined
    @State var cameraState: PermissionState = .notDetermined
    @State var isRequestingMic = false
    @State var isRequestingCamera = false
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        Form {
            Section(header: Text(viewModel.mediaPermissionsSectionTitle)) {
                permissionRow(
                    label: viewModel.microphonePermissionLabel,
                    caption: viewModel.microphonePermissionCaption,
                    state: micState,
                    isRequesting: isRequestingMic,
                    onEnable: { Task { await request(.microphone) } }
                )
                permissionRow(
                    label: viewModel.cameraPermissionLabel,
                    caption: viewModel.cameraPermissionCaption,
                    state: cameraState,
                    isRequesting: isRequestingCamera,
                    onEnable: { Task { await request(.camera) } }
                )
            }
        }
        .task {
            refresh()
        }
        // The two switches belong to the OS, so the only way to turn one back
        // on once it is denied is the system settings app. Re-read on return,
        // or the screen keeps reporting the state the user just left behind.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refresh()
            }
        }
    }

    @ViewBuilder
    private func permissionRow(
        label: String,
        caption: String,
        state: PermissionState,
        isRequesting: Bool,
        onEnable: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text(state.subtitle)
                    .foregroundStyle(.secondary)
            }
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }

        switch state {
        case .notDetermined:
            Button(action: onEnable) {
                HStack {
                    Text(state.actionTitle)
                    Spacer()
                    if isRequesting {
                        ProgressView().scaleEffect(0.8)
                    }
                }
            }
            .disabled(isRequesting)
        case .denied:
            // Once denied, asking again is a no-op the OS answers instantly,
            // so send the user where the switch actually lives.
            Button(viewModel.openSystemSettingsLabel) {
                PermissionService.shared.openAppSettings()
            }
        case .granted:
            EmptyView()
        }
    }

    private func refresh() {
        micState = PermissionService.shared.captureStatus(for: .microphone)
        cameraState = PermissionService.shared.captureStatus(for: .camera)
    }

    private func request(_ kind: CapturePermissionKind) async {
        switch kind {
        case .microphone: isRequestingMic = true
        case .camera: isRequestingCamera = true
        }
        defer {
            switch kind {
            case .microphone: isRequestingMic = false
            case .camera: isRequestingCamera = false
            }
        }

        let result = await PermissionService.shared.requestCapturePermission(for: kind)
        switch kind {
        case .microphone: micState = result
        case .camera: cameraState = result
        }
    }
}
