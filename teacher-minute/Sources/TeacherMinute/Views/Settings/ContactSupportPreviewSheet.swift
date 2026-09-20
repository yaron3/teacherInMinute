//
//  ContactSupportPreviewSheet.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct ContactSupportPreviewSheet: View {
    let viewModel: any SettingsViewModeling
    let request: ContactSupportRequest
    let isSubmitting: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(request.previewRows, id: \.0) { title, value in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(value)
                                .font(.body)
                                .foregroundStyle(.primary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(viewModel.contactSupportPreviewSectionTitle)
                }
            }
            .navigationTitle(viewModel.previewTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(viewModel.cancelLabel) {
                        onCancel()
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSubmit()
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(viewModel.sendLabel)
                        }
                    }
                    .disabled(isSubmitting)
                }
            }
        }
    }
}
