//
//  ChangePasswordSettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct ChangePasswordSettingsView: View {
    let viewModel: any SettingsViewModeling

    var body: some View {
        Form {
            Section {
                Text(viewModel.changePasswordIntroText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(viewModel.sendResetEmailLabel) {
                    viewModel.sendPasswordReset()
                }
            }
        }
    }
}
