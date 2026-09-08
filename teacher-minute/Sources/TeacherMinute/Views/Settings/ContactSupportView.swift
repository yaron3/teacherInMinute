//
//  ContactSupportView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct ContactSupportView: View {
    let viewModel: any SettingsViewModeling

    var titleBinding: Binding<String> {
        Binding {
            viewModel.contactSupportTitle
        } set: { value in
            viewModel.updateContactSupportTitle(value)
        }
    }

    var descriptionBinding: Binding<String> {
        Binding {
            viewModel.contactSupportDescription
        } set: { value in
            viewModel.updateContactSupportDescription(value)
        }
    }

    var body: some View {
        Form {
            Section {
                Text(viewModel.contactSupportIntroText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text(viewModel.contactSupportTitleSectionTitle)) {
                TextField(viewModel.contactSupportTitlePlaceholder, text: titleBinding)
                    .textInputAutocapitalization(.sentences)
                Text(viewModel.contactSupportTitleCounterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Section(header: Text(viewModel.contactSupportDescriptionSectionTitle)) {
                TextEditor(text: descriptionBinding)
                    .frame(minHeight: 160)
                Text(viewModel.contactSupportDescriptionCounterText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    viewModel.previewContactSupport()
                } label: {
                    HStack {
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(viewModel.contactSupportSubmitLabel)
                    }
                }
                .disabled(viewModel.isLoading || viewModel.isSubmittingContactSupport)
            }
        }
        .onAppear {
            viewModel.contactSupportAppeared()
        }
    }
}
