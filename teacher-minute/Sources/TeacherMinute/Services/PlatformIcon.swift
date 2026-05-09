//
//  PlatformIcon.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 09/05/2026.
//

import SwiftUI

/// Cross-platform icon: uses SF Symbols on iOS, emoji text on Android.
struct PlatformIcon: View {
    let systemName: String
    var size: CGFloat = 20
    var weight: Font.Weight = .regular
    var color: Color = .primary

    var body: some View {
#if os(Android)
        Text(Self.emoji(for: systemName))
            .font(.system(size: size * 0.9))
            .frame(width: size, height: size)
#else
        Image(systemName: systemName)
            .font(.system(size: size, weight: weight))
            .foregroundStyle(color)
#endif
    }

    static func emoji(for systemName: String) -> String {
        switch systemName {
        case "moon.fill":                           return "🌙"
        case "antenna.radiowaves.left.and.right":   return "📡"
        case "checkmark.seal":                      return "✅"
        case "checkmark.seal.fill":                 return "✅"
        case "mic.fill":                            return "🎤"
        case "video.fill":                          return "📷"
        case "circle.fill":                         return "🟢"
        case "bell.fill":                           return "🔔"
        case "person.crop.circle.fill":             return "👤"
        case "xmark":                               return "✕"
        case "wifi":                                return "📶"
        case "camera.fill":                         return "📸"
        case "chevron.right":                       return "›"
        case "star.fill":                           return "⭐"
        default:                                    return "●"
        }
    }
}
