import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension Color {

    private static func adaptive(
        light: (CGFloat, CGFloat, CGFloat),
        dark: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        #if canImport(UIKit)
        Color(uiColor: UIColor { traits in
            let c = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0 / 255, green: c.1 / 255, blue: c.2 / 255, alpha: 1)
        })
        #else
        Color(red: light.0 / 255, green: light.1 / 255, blue: light.2 / 255)
        #endif
    }

    // MARK: - Text

    static let appPrimaryText = adaptive(
        light: (17, 24, 39),
        dark: (243, 244, 246)
    )

    static let appSecondaryText = adaptive(
        light: (107, 114, 128),
        dark: (163, 168, 178)
    )

    // MARK: - Accent

    static let appPink = adaptive(
        light: (236, 64, 153),
        dark: (244, 114, 182)
    )

    static let appPinkSoft = adaptive(
        light: (253, 242, 248),
        dark: (55, 20, 40)
    )

    static let appPurple = adaptive(
        light: (124, 58, 237),
        dark: (163, 112, 255)
    )

    static let appPurpleSoft = adaptive(
        light: (245, 243, 255),
        dark: (40, 25, 65)
    )

    static let appGreen = adaptive(
        light: (16, 185, 129),
        dark: (52, 211, 153)
    )

    static let appGreenSoft = adaptive(
        light: (209, 250, 229),
        dark: (15, 45, 32)
    )

    static let appOrange = adaptive(
        light: (245, 158, 11),
        dark: (251, 191, 36)
    )

    // MARK: - Backgrounds & Surfaces

    static let appGrayBackground = adaptive(
        light: (249, 250, 251),
        dark: (24, 24, 27)
    )

    static let appCardBackground = adaptive(
        light: (255, 255, 255),
        dark: (36, 36, 40)
    )

    // MARK: - Borders

    static let appBorder = adaptive(
        light: (229, 231, 235),
        dark: (55, 55, 65)
    )

    // MARK: - Auth Aliases

    static let authPrimaryText = appPrimaryText
    static let authSecondaryText = appSecondaryText
    static let authPink = appPink
    static let authPinkSoft = appPinkSoft
    static let authPurple = appPurple
    static let authPurpleSoft = appPurpleSoft
    static let authGreen = appGreen
    static let authOrange = appOrange

    static let authFieldBackground = adaptive(
        light: (249, 250, 251),
        dark: (30, 30, 36)
    )

    static let authFieldBorder = adaptive(
        light: (239, 242, 247),
        dark: (50, 52, 60)
    )

    static let authIcon = adaptive(
        light: (156, 163, 175),
        dark: (156, 163, 175)
    )

    static let authDivider = adaptive(
        light: (229, 231, 235),
        dark: (45, 45, 52)
    )

    static let authSocialBorder = adaptive(
        light: (229, 231, 235),
        dark: (45, 45, 52)
    )
}
