//
//  HelpSupportView.swift
//  teacher-minute
//
//  The side menu's Help & Support section: the Contact Support form from
//  Settings, reached in one step instead of two.
//

import SwiftUI

struct HelpSupportView: View {
    @State var viewModel: any SettingsViewModeling

    init(role: AppUserMode, viewModel: (any SettingsViewModeling)? = nil) {
        self._viewModel = State(wrappedValue: viewModel ?? SettingsViewModel(role: role))
    }

    var body: some View {
        ZStack {
            if AppTheme.isBrand {
                brandScreen
            } else {
                standardScreen
            }
        }
        .appDialog(
            viewModel.alertTitle,
            isPresented: isShowingAlert,
            message: viewModel.alertMessage ?? "",
            actions: [AppDialogAction(viewModel.okLabel)]
        )
        .sheet(item: contactSupportPreview) { request in
            ContactSupportPreviewSheet(
                viewModel: viewModel,
                request: request,
                isSubmitting: viewModel.isSubmittingContactSupport,
                onCancel: { viewModel.cancelContactSupportPreview() },
                onSubmit: { viewModel.submitContactSupport() }
            )
        }
    }

    /// Instant Teacher's look: a section like the others, with the tab bar,
    /// and the contact form in a brand card.
    var brandScreen: some View {
        BrandTabScreen {
            VStack(spacing: 0) {
                BrandPageHeader(label: viewModel.helpSupportTitle, title: viewModel.helpSupportTitle) {
                    BrandMenuButton()
                }
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        BrandPageHero(title: viewModel.helpSupportTitle, subtitle: viewModel.contactSupportIntroText)
                        ContactSupportView(viewModel: viewModel, embedded: true)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    var standardScreen: some View {
        NavigationStack {
#if os(Android)
            // The title and menu button are drawn above the form instead; see
            // SideMenuSectionHeader.
            VStack(spacing: 0) {
                SideMenuSectionHeader(title: viewModel.helpSupportTitle)
                ContactSupportView(viewModel: viewModel)
            }
            .toolbar(.hidden, for: .navigationBar)
#else
            ContactSupportView(viewModel: viewModel)
                .navigationTitle(viewModel.helpSupportTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        SideMenuButton(size: 36)
                    }
                }
#endif
        }
    }

    // The view model is held as an existential, so the bindings SwiftUI needs
    // are built by hand instead of through `$viewModel`.
    var contactSupportPreview: Binding<ContactSupportRequest?> {
        Binding {
            viewModel.contactSupportPreview
        } set: { request in
            viewModel.contactSupportPreview = request
        }
    }

    var isShowingAlert: Binding<Bool> {
        Binding {
            viewModel.showAlert
        } set: { isPresented in
            viewModel.showAlert = isPresented
        }
    }
}
