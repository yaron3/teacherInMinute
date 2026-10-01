//
//  ContactSupportView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct ContactSupportView: View {
    let viewModel: any SettingsViewModeling
    /// Whether the form sits inside Help & Support, which draws the page
    /// around it, or is a page of its own, Contact Us.
    var embedded = false

    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }

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
        ZStack {
            if embedded {
                form
            } else {
                BrandSubpage(
                    label: viewModel.settingsTitle,
                    title: viewModel.settingsPageTitle(SettingsDestination.contactUs.title),
                    backLabel: viewModel.backLabel
                ) {
                    BrandPageHero(title: SettingsDestination.contactUs.title, subtitle: viewModel.contactSupportIntroText)
                    form
                }
            }
        }
        .onAppear {
            viewModel.contactSupportAppeared()
        }
    }

    /// The title and description as the brand's fields, each with its count,
    /// and the preview as the brand's button.
    var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                BrandTextField(
                    title: viewModel.contactSupportTitleSectionTitle,
                    placeholder: viewModel.contactSupportTitlePlaceholder,
                    text: titleBinding,
                    autocapitalization: .sentences
                )
                counter(viewModel.contactSupportTitleCounterText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(viewModel.contactSupportDescriptionSectionTitle)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(theme.brandSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextEditor(text: descriptionBinding)
                    .font(.system(size: 16))
                    .foregroundStyle(theme.onDarkFill)
                    .tint(theme.brandActionBackground)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 160)
                    .background(theme.brandBackgroundTop)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(theme.brandControlBorder, lineWidth: 1)
                    }
                counter(viewModel.contactSupportDescriptionCounterText)
            }

            BrandPrimaryButton(
                title: viewModel.contactSupportSubmitLabel,
                isLoading: viewModel.isLoading,
                isEnabled: !viewModel.isSubmittingContactSupport
            ) {
                viewModel.previewContactSupport()
            }
        }
        .brandCard()
    }

    func counter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(theme.brandSecondaryText)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
