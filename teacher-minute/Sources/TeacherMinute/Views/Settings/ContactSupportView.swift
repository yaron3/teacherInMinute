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
#if os(Android)
    @State var showsAttachmentSourceDialog = false
#endif

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
#if os(Android)
        // The brand's dialog, as iOS's photo chooser is.
        .appDialog(
            viewModel.photoSourceDialogTitle,
            isPresented: $showsAttachmentSourceDialog,
            actions: [
                AppDialogAction(viewModel.photoSourceTakePhotoLabel) {
                    Task { await viewModel.pickContactSupportAttachment(fromCamera: true) }
                },
                AppDialogAction(viewModel.photoSourceLibraryLabel) {
                    Task { await viewModel.pickContactSupportAttachment(fromCamera: false) }
                },
                AppDialogAction(viewModel.photoSourceCancelLabel, kind: .cancel)
            ]
        )
#endif
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

            attachmentsSection

            BrandPrimaryButton(
                title: viewModel.contactSupportSubmitLabel,
                isLoading: viewModel.isLoading,
                isEnabled: !viewModel.isSubmittingContactSupport
            ) {
                trackTap("contact_support_submit")
                viewModel.previewContactSupport()
            }
        }
        .brandCard()
    }

    /// The images going with the request, each with the `×` that takes it
    /// off, and a tile that adds another while there is room.
    var attachmentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.contactSupportAttachmentsSectionTitle)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.brandSecondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(viewModel.contactSupportAttachmentsHint)
                .font(.system(size: 13))
                .foregroundStyle(theme.brandSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 10) {
                ForEach(0..<viewModel.contactSupportAttachments.count, id: \.self) { index in
                    attachmentTile(index)
                }
                if viewModel.canAddContactSupportAttachment {
                    addAttachmentButton
                }
                Spacer(minLength: 0)
            }
            counter(viewModel.contactSupportAttachmentsCounterText)
        }
    }

    func attachmentTile(_ index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            LocalPhotoThumbnail(
                data: viewModel.contactSupportAttachments[index],
                maxPointSize: 96,
                previewDirectory: ContactSupportService.attachmentPreviewDirectory,
                replacesEarlierPreviews: false
            )
            .frame(width: 72, height: 96)
            .background(theme.brandBackgroundTop)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                trackTap("contact_support_remove_attachment", detail: "\(index)")
                viewModel.removeContactSupportAttachment(at: index)
            } label: {
                Circle()
                    .fill(theme.onDarkFill.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .overlay {
                        PlatformIcon(systemName: "xmark", size: 10, weight: .bold, color: theme.brandPanelBackground)
                    }
                    .padding(4)
            }
            .buttonStyle(.plain)
#if !os(Android)
            // SkipUI has no string `accessibilityLabel`.
            .accessibilityLabel(viewModel.contactSupportRemoveAttachmentLabel)
#endif
            .accessibilityIdentifier("contact_support_remove_attachment_\(index)")
        }
        .frame(width: 72, height: 96)
    }

    var addAttachmentTile: some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(theme.brandControlBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            .overlay {
                PlatformIcon(systemName: "plus", size: 22, weight: .semibold, color: theme.brandSecondaryText)
            }
            .frame(width: 72, height: 96)
            .tappableFrame()
    }

#if os(Android)
    var addAttachmentButton: some View {
        Button {
            trackTap("contact_support_add_attachment")
            showsAttachmentSourceDialog = true
        } label: {
            addAttachmentTile
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("contact_support_add_attachment")
    }
#else
    /// Counted by `PhotoSourceButton` itself (`photo_source_open`).
    var addAttachmentButton: some View {
        PhotoSourceButton(viewModel: viewModel, onImageData: { data in
            viewModel.addContactSupportAttachment(data)
        }) {
            addAttachmentTile
        }
        .accessibilityLabel(viewModel.contactSupportAddAttachmentLabel)
        .accessibilityIdentifier("contact_support_add_attachment")
    }
#endif

    func counter(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(theme.brandSecondaryText)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
