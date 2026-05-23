//
//  AppTheme.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 15/05/2026.
//


import SwiftUI

struct AppTheme {
    let colorScheme: ColorScheme

    // MARK: - Helpers

    func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        colorScheme == .dark
        ? rgb(dark)
        : rgb(light)
    }

    func rgb(_ value: (Double, Double, Double)) -> Color {
        Color(
            red: value.0 / 255.0,
            green: value.1 / 255.0,
            blue: value.2 / 255.0
        )
    }

    // MARK: - Text
	var red: Color {
	  adaptive(
		light: (255, 0,0),
		dark: (255, 0,0)
	  )
	}
    
	var yellow: Color {
	adaptive(
	  light: (255, 204, 0),
	  dark: (255, 204, 0)
	)
	  
	
  }
  var white: Color {
	adaptive(
	  light: (255, 255, 255),
	  dark: (255, 255, 255)
	)
  }
	var appPrimaryText: Color {
        adaptive(
            light: (17, 24, 39),
            dark: (243, 244, 246)
        )
    }

    var appSecondaryText: Color {
        adaptive(
            light: (107, 114, 128),
            dark: (163, 168, 178)
        )
    }

    // MARK: - Accent

    var appPink: Color {
        adaptive(
            light: (236, 64, 153),
            dark: (244, 114, 182)
        )
    }

    var appPinkSoft: Color {
        adaptive(
            light: (253, 242, 248),
            dark: (55, 20, 40)
        )
    }

    var appPurple: Color {
        adaptive(
            light: (124, 58, 237),
            dark: (163, 112, 255)
        )
    }

    var appPurpleSoft: Color {
        adaptive(
            light: (245, 243, 255),
            dark: (40, 25, 65)
        )
    }

    var appGreen: Color {
        adaptive(
            light: (16, 185, 129),
            dark: (52, 211, 153)
        )
    }

    var appGreenSoft: Color {
        adaptive(
            light: (209, 250, 229),
            dark: (15, 45, 32)
        )
    }

    var appOrange: Color {
        adaptive(
            light: (245, 158, 11),
            dark: (251, 191, 36)
        )
    }

    var appTeal: Color {
        adaptive(
            light: (20, 184, 166),
            dark: (45, 212, 191)
        )
    }

    var appTealSoft: Color {
        adaptive(
            light: (224, 247, 244),
            dark: (15, 56, 52)
        )
    }

    // MARK: - Backgrounds & Surfaces

    var appGrayBackground: Color {
        adaptive(
            light: (249, 250, 251),
            dark: (24, 24, 27)
        )
    }

    var appCardBackground: Color {
        adaptive(
            light: (255, 255, 255),
            dark: (36, 36, 40)
        )
    }

    var appCardBackgroundShadow: Color {
        adaptive(
            light: (20, 20, 20),
            dark: (236, 236, 240)
        )
    }

    // MARK: - Borders

    var appBorder: Color {
        adaptive(
            light: (120, 120, 120),
            dark: (85, 85, 85)
        )
    }

    // MARK: - Auth Aliases

    var authPrimaryText: Color {
        appPrimaryText
    }

    var authSecondaryText: Color {
        appSecondaryText
    }

    var authPink: Color {
        appPink
    }

    var authPinkSoft: Color {
        appPinkSoft
    }

    var authPurple: Color {
        appPurple
    }

    var authPurpleSoft: Color {
        appPurpleSoft
    }

    var authGreen: Color {
        appGreen
    }

    var authOrange: Color {
        appOrange
    }

    var authFieldBackground: Color {
        adaptive(
            light: (249, 250, 251),
            dark: (30, 30, 36)
        )
    }

    var authFieldBorder: Color {
        adaptive(
            light: (239, 242, 247),
            dark: (50, 52, 60)
        )
    }

    var authIcon: Color {
        adaptive(
            light: (156, 163, 175),
            dark: (156, 163, 175)
        )
    }

    var authDivider: Color {
        adaptive(
            light: (229, 231, 235),
            dark: (45, 45, 52)
        )
    }

    var authSocialBorder: Color {
        adaptive(
            light: (229, 231, 235),
            dark: (45, 45, 52)
        )
    }

    // MARK: - Generic Aliases

    var primaryText: Color {
        adaptive(
            light: (18, 24, 40),
            dark: (243, 244, 246)
        )
    }

    var primaryBackground: Color {
        adaptive(
            light: (243, 244, 246),
            dark: (18, 24, 40)
        )
    }

    var secondaryText: Color {
        adaptive(
            light: (102, 112, 133),
            dark: (163, 168, 178)
        )
    }

    var previewBackground: Color {
        adaptive(
            light: (252, 252, 253),
            dark: (28, 28, 32)
        )
    }

    // MARK: - Green Status

    var greenText: Color {
        adaptive(
            light: (2, 122, 72),
            dark: (52, 211, 153)
        )
    }

    var greenBackground: Color {
        adaptive(
            light: (236, 253, 243),
            dark: (15, 45, 32)
        )
    }

    var greenBorder: Color {
        adaptive(
            light: (186, 244, 210),
            dark: (30, 80, 55)
        )
    }

    // MARK: - Gray Badge

    var badgeGrayText: Color {
        adaptive(
            light: (52, 64, 84),
            dark: (200, 205, 215)
        )
    }

    var grayBadgeBackground: Color {
        adaptive(
            light: (249, 250, 251),
            dark: (36, 36, 40)
        )
    }

    var grayBadgeBorder: Color {
        adaptive(
            light: (242, 244, 247),
            dark: (55, 55, 65)
        )
    }
}

#if os(iOS)
private struct AppThemeSwatch: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8)
                .fill(color)
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.25), lineWidth: 0.5)
                )
            Text(name)
                .font(.system(size: 14, design: .monospaced))
            Spacer()
        }
    }
}

private struct AppThemePreviewView: View {
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
	AppTheme(colorScheme: colorScheme)
  }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section("Text", swatches: [
                    ("red", theme.red),
                    ("yellow", theme.yellow),
                    ("white", theme.white),
                    ("appPrimaryText", theme.appPrimaryText),
                    ("appSecondaryText", theme.appSecondaryText)
                ])

                section("Accent", swatches: [
                    ("appPink", theme.appPink),
                    ("appPinkSoft", theme.appPinkSoft),
                    ("appPurple", theme.appPurple),
                    ("appPurpleSoft", theme.appPurpleSoft),
                    ("appGreen", theme.appGreen),
                    ("appGreenSoft", theme.appGreenSoft),
                    ("appOrange", theme.appOrange),
                    ("appTeal", theme.appTeal),
                    ("appTealSoft", theme.appTealSoft)
                ])

                section("Backgrounds & Surfaces", swatches: [
                    ("appGrayBackground", theme.appGrayBackground),
                    ("appCardBackground", theme.appCardBackground),
                    ("appCardBackgroundShadow", theme.appCardBackgroundShadow)
                ])

                section("Borders", swatches: [
                    ("appBorder", theme.appBorder)
                ])

                section("Auth", swatches: [
                    ("authFieldBackground", theme.authFieldBackground),
                    ("authFieldBorder", theme.authFieldBorder),
                    ("authIcon", theme.authIcon),
                    ("authDivider", theme.authDivider),
                    ("authSocialBorder", theme.authSocialBorder)
                ])

                section("Generic", swatches: [
                    ("primaryText", theme.primaryText),
                    ("primaryBackground", theme.primaryBackground),
                    ("secondaryText", theme.secondaryText),
                    ("previewBackground", theme.previewBackground)
                ])

                section("Green Status", swatches: [
                    ("greenText", theme.greenText),
                    ("greenBackground", theme.greenBackground),
                    ("greenBorder", theme.greenBorder)
                ])

                section("Gray Badge", swatches: [
                    ("badgeGrayText", theme.badgeGrayText),
                    ("grayBadgeBackground", theme.grayBadgeBackground),
                    ("grayBadgeBorder", theme.grayBadgeBorder)
                ])
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func section(_ title: String, swatches: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            VStack(spacing: 6) {
                ForEach(swatches, id: \.0) { item in
                    AppThemeSwatch(name: item.0, color: item.1)
                }
            }
        }
    }
}

#Preview("Light") {
    AppThemePreviewView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    AppThemePreviewView()
        .preferredColorScheme(.dark)
}

#endif
