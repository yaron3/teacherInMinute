//
//  AboutSettingsView.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 06/05/2026.
//

import SwiftUI

struct AboutSettingsView: View {
    let viewModel: any SettingsViewModeling
    @Environment(\.colorScheme) var colorScheme
    var theme: AppTheme {
        AppTheme(colorScheme: colorScheme)
    }
    var body: some View {
        ZStack {
            BrandSubpage(
                label: viewModel.settingsTitle,
                title: viewModel.settingsPageTitle(SettingsDestination.about.title),
                backLabel: viewModel.backLabel
            ) {
                BrandPageHero(title: SettingsDestination.about.title)
                BrandSettingsRows(rows: viewModel.aboutSection.rows) { row in
                    viewModel.select(row)
                }
            }
            // The EULA's address is fetched before it opens, so the page shows
            // it is working meanwhile.
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(1.4)
                    .tint(theme.onDarkFill)
            }
        }
        // A page pushed over Settings covers the dialog Settings raises, so
        // this one raises it too.
        .appDialog(
            viewModel.alertTitle,
            isPresented: isShowingAlert,
            message: viewModel.alertMessage ?? "",
            actions: [AppDialogAction(viewModel.okLabel)]
        )
    }

    var isShowingAlert: Binding<Bool> {
        Binding {
            viewModel.showAlert
        } set: { isPresented in
            viewModel.showAlert = isPresented
        }
    }
}
