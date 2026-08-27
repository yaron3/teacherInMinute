//
//  AppTheme.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 15/05/2026.
//
//  One palette for the whole app. Every token is named for the job it does —
//  `cardBackground`, `separator`, `danger` — never for the color it happens to
//  be, so a color can be retuned without renaming call sites. A token is only
//  ever used in its own role: text tokens are never used as fills, and surface
//  tokens are never used as text.
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

    /// Body copy, titles, and icons on a plain surface.
    var primaryText: Color {
        adaptive(
            light: (0, 0, 0),
            dark: (255, 255, 255)
        )
    }

    /// Captions, secondary labels, placeholder icons.
    var secondaryText: Color {
        adaptive(
            light: (110, 110, 110),
            dark: (160, 160, 160)
        )
    }

    /// Text drawn on a `primaryText` fill.
    var invertedText: Color {
        adaptive(
            light: (255, 255, 255),
            dark: (0, 0, 0)
        )
    }

    /// Text and icons drawn on `accent`, `positive`, `danger`, a video feed or
    /// any other dark fill. White in both schemes — those fills stay dark.
    var onAccentText: Color {
        adaptive(
		  light: (0, 0,0),
            dark: (255, 255, 255)
        )
    }

    // MARK: - Surfaces

    /// Page background behind everything else.
    var screenBackground: Color {
        adaptive(
            light: (255, 255, 255),
            dark: (15, 15, 17)
        )
    }

    /// Cards, tiles and grouped panels sitting on `screenBackground`.
    var cardBackground: Color {
        adaptive(
            light: (242, 242, 244),
            dark: (25, 25, 28)
        )
    }

    /// Text fields, search bars and other editable controls.
    var fieldBackground: Color {
        adaptive(
            light: (242, 242, 244),
            dark: (35, 35, 38)
        )
    }

    /// Dimming layer behind a modal or full-screen overlay. Always used with an
    /// opacity, and black in both schemes — it darkens, it never tints.
    var scrim: Color {
        adaptive(
            light: (0, 0, 0),
            dark: (0, 0, 0)
        )
    }

    /// Behind a camera feed or video frame — stays black in both schemes so the
    /// picture never sits on a tinted surface.
    var videoBackground: Color {
        adaptive(
            light: (0, 0, 0),
            dark: (0, 0, 0)
        )
    }

    /// Drop shadow under floating panels. Always used with an opacity.
    var cardShadow: Color {
        adaptive(
            light: (20, 20, 20),
            dark: (236, 236, 240)
        )
    }

    // MARK: - Accent

    /// Primary action fill, selected state, highlight.
    var accent: Color {
        adaptive(
            light: (67, 75, 214),
            dark: (100, 100, 255)
        )
    }

    /// Deeper accent for pressed/selected fills and accent gradients.
    var accentStrong: Color {
        adaptive(
            light: (74, 60, 190),
            dark: (46, 42, 158)
        )
    }

    /// Tinted surface for accent-on-surface treatments — accent chips, badges
    /// and icon tiles that must stay legible behind `accent` content.
    var accentBackground: Color {
        adaptive(
            light: (238, 236, 255),
            dark: (38, 34, 74)
        )
    }

    // MARK: - Lines & controls

    /// Hairline rule between rows and sections.
    var separator: Color {
        adaptive(
            light: (228, 228, 231),
            dark: (58, 58, 62)
        )
    }

    /// Outline around fields, chips and outlined tiles.
    var controlBorder: Color {
        adaptive(
            light: (228, 228, 231),
            dark: (58, 58, 62)
        )
    }

    /// Fill for a control that is present but not actionable yet — a send
    /// button with nothing to send, a disabled toolbar item.
    var controlDisabled: Color {
        adaptive(
            light: (120, 120, 120),
            dark: (85, 85, 85)
        )
    }

    // MARK: - Status

    /// Online, ready, succeeded.
    var positive: Color {
        adaptive(
            light: (0, 122, 71),
            dark: (34, 197, 94)
        )
    }

    var positiveBackground: Color {
        adaptive(
            light: (226, 242, 237),
            dark: (30, 59, 52)
        )
    }

    var positiveBorder: Color {
        adaptive(
            light: (186, 244, 210),
            dark: (30, 80, 55)
        )
    }

    /// Pending, waiting, needs attention.
    var warning: Color {
        adaptive(
            light: (176, 132, 0),
            dark: (245, 197, 24)
        )
    }

    var warningBackground: Color {
        adaptive(
            light: (255, 247, 219),
            dark: (58, 45, 10)
        )
    }

    var warningBorder: Color {
        adaptive(
            light: (245, 220, 140),
            dark: (92, 72, 20)
        )
    }

    /// Errors, recording indicator, destructive actions.
    var danger: Color {
        adaptive(
            light: (200, 30, 30),
            dark: (248, 113, 113)
        )
    }

    var dangerBackground: Color {
        adaptive(
            light: (253, 232, 232),
            dark: (60, 24, 24)
        )
    }

    /// Neutral informational accent — video/live markers, secondary chips.
    var info: Color {
        adaptive(
            light: (20, 184, 166),
            dark: (45, 212, 191)
        )
    }

    /// Filled star in a rating control.
    var ratingStar: Color {
        adaptive(
            light: (255, 204, 0),
            dark: (255, 204, 0)
        )
    }

    // MARK: - Chat bubbles

    /// Messages sent by the current user.
    var outgoingBubbleBackground: Color {
        adaptive(
            light: (67, 75, 214),
            dark: (100, 100, 255)
        )
    }

    var outgoingBubbleText: Color {
        adaptive(
            light: (255, 255, 255),
            dark: (255, 255, 255)
        )
    }

    /// Messages received from the other participant.
    var incomingBubbleBackground: Color {
        adaptive(
            light: (200, 200, 214),
            dark: (50, 50, 50)
        )
    }

    var incomingBubbleText: Color {
        adaptive(
            light: (0, 0, 0),
            dark: (255, 255, 255)
        )
    }

    // MARK: - Neutral badge

    var badgeText: Color {
        adaptive(
            light: (52, 64, 84),
            dark: (200, 205, 215)
        )
    }

    var badgeBackground: Color {
        adaptive(
            light: (249, 250, 251),
            dark: (36, 36, 40)
        )
    }

    var badgeBorder: Color {
        adaptive(
            light: (242, 244, 247),
            dark: (55, 55, 65)
        )
    }

    // MARK: - Whiteboard pen palette
    //
    // The one place where a color name *is* the purpose: these are the swatches
    // the user picks between when drawing, so they are tuned to stay apart from
    // each other rather than to match any UI role.

    var penInk: Color {
        adaptive(
            light: (0, 0, 0),
            dark: (255, 255, 255)
        )
    }

    var penPink: Color {
        adaptive(
            light: (153, 64, 236),
            dark: (182, 114, 244)
        )
    }

    var penPurple: Color {
        adaptive(
            light: (124, 58, 237),
            dark: (163, 112, 255)
        )
    }

    var penGreen: Color {
        adaptive(
            light: (16, 185, 129),
            dark: (52, 211, 153)
        )
    }

    var penOrange: Color {
        adaptive(
            light: (245, 158, 11),
            dark: (251, 191, 36)
        )
    }

    var penTeal: Color {
        adaptive(
            light: (20, 184, 166),
            dark: (45, 212, 191)
        )
    }

    var penRed: Color {
        adaptive(
            light: (255, 0, 0),
            dark: (255, 82, 82)
        )
    }

    var penYellow: Color {
        adaptive(
            light: (255, 204, 0),
            dark: (255, 214, 51)
        )
    }
  
  var ctaBackground : Color {
	adaptive(
	  light: (203, 60, 57),
	  dark: (203, 60, 57)
	)
  }
  
  var ctaForeground : Color {
	adaptive(
	  light: (255, 255, 255),
	  dark: (255, 255, 255)
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
                    ("primaryText", theme.primaryText),
                    ("secondaryText", theme.secondaryText),
                    ("invertedText", theme.invertedText),
                    ("onAccentText", theme.onAccentText)
                ])

                section("Surfaces", swatches: [
                    ("screenBackground", theme.screenBackground),
                    ("cardBackground", theme.cardBackground),
                    ("fieldBackground", theme.fieldBackground),
                    ("scrim", theme.scrim),
                    ("videoBackground", theme.videoBackground),
                    ("cardShadow", theme.cardShadow)
                ])

                section("Accent", swatches: [
                    ("accent", theme.accent),
                    ("accentStrong", theme.accentStrong),
                    ("accentBackground", theme.accentBackground)
                ])

                section("Lines & controls", swatches: [
                    ("separator", theme.separator),
                    ("controlBorder", theme.controlBorder),
                    ("controlDisabled", theme.controlDisabled)
                ])

                section("Status", swatches: [
                    ("positive", theme.positive),
                    ("positiveBackground", theme.positiveBackground),
                    ("positiveBorder", theme.positiveBorder),
                    ("warning", theme.warning),
                    ("warningBackground", theme.warningBackground),
                    ("warningBorder", theme.warningBorder),
                    ("danger", theme.danger),
                    ("dangerBackground", theme.dangerBackground),
                    ("info", theme.info),
                    ("ratingStar", theme.ratingStar)
                ])

                section("Chat bubbles", swatches: [
                    ("outgoingBubbleBackground", theme.outgoingBubbleBackground),
                    ("outgoingBubbleText", theme.outgoingBubbleText),
                    ("incomingBubbleBackground", theme.incomingBubbleBackground),
                    ("incomingBubbleText", theme.incomingBubbleText)
                ])

                section("Neutral badge", swatches: [
                    ("badgeText", theme.badgeText),
                    ("badgeBackground", theme.badgeBackground),
                    ("badgeBorder", theme.badgeBorder)
                ])

                section("Whiteboard pens", swatches: [
                    ("penInk", theme.penInk),
                    ("penPink", theme.penPink),
                    ("penPurple", theme.penPurple),
                    ("penGreen", theme.penGreen),
                    ("penOrange", theme.penOrange),
                    ("penTeal", theme.penTeal),
                    ("penRed", theme.penRed),
                    ("penYellow", theme.penYellow)
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
