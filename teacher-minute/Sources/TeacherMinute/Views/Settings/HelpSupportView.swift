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
        NavigationStack {
            ContactSupportView(viewModel: viewModel)
                .navigationTitle(viewModel.helpSupportTitle)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        SideMenuButton(size: 36)
                    }
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
