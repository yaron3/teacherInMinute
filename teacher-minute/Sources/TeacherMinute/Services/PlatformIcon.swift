//
//  PlatformIcon.swift
//  teacher-minute
//
//  Created by Yaron Jackoby on 09/05/2026.
//

import SwiftUI
import SkipFuse

/// Cross-platform icon: uses SF Symbols on iOS, emoji text on Android.
///

struct PlatformIcon: View {
  
	let systemName: String
	var size: CGFloat = 20
	var weight: Font.Weight = .regular
	var color: Color = .primary
  @Environment(\.layoutDirection) var layoutDirection
  
  private static let bundledIcons: Set<String> = [
	"bubble.left.and.bubble.right.fill",
	"google-logo",
	"teaching_tab_icon"
  ]
  
  private var resolvedName: String {
	guard layoutDirection == .rightToLeft else { return systemName }
	if systemName == "chevron.right" { return "chevron.left" }
		if systemName == "chevron.left"  { return "chevron.right" }
	if systemName == "arrow.right"   { return "arrow.left" }
		if systemName == "arrow.left"    { return "arrow.right" }
	return systemName
  }
  
  var body: some View {
	if Self.bundledIcons.contains(resolvedName) {
	  Image(resolvedName, bundle: .module)
		.resizable()
		.frame(width: size, height: size)
	} else {
#if os(Android)
	  Text(Self.emoji(for: resolvedName))
		.font(.system(size: size))
		.foregroundStyle(color)
#else
	  Image(systemName: resolvedName)
		.font(.system(size: size, weight: weight))
		.foregroundStyle(color)
#endif
	}
	
  }
  
  static func emoji(for systemName: String) -> String {
	switch systemName {
	  case "moon.fill":                         return "🌙"
	  case "antenna.radiowaves.left.and.right": return "📡"
	  case "checkmark.seal":                    return "☑️"
	  case "checkmark.seal.fill":               return "✅"
	  case "link":                              return "🔗"
	  case "checkmark.circle.fill":             return "✓"
	  case "questionmark.circle":               return "?"
	  case "photo.fill":                        return "▧"
	  case "mic.fill":                          return "🎤"
	  case "speaker.wave.2.fill":               return "🔊"
	  case "video.fill":                        return "📷"
	  case "circle.fill":                       return "🟢"
	  case "bell.fill":                         return "🔔"
	  // Unfilled and badged variants of symbols already mapped above: iOS picks
	  // them for weight, but Android has one emoji either way, so they must be
	  // listed explicitly or they fall through to the "missing" dot below.
	  case "bell":                              return "🔔"
	  case "bell.badge.fill":                   return "🔔"
	  case "doc.text":                          return "📄"
	  case "graduationcap":                     return "🎓"
	  case "photo":                             return "▧"
	  case "calendar":                          return "📅"
	  case "arrow.clockwise":                   return "↻"
	  case "arrow.down.doc":                    return "⬇"
	  case "arrow.up.doc.fill":                 return "⬆"
	  case "exclamationmark.triangle.fill":     return "⚠️"
	  // "…slash" symbols mean the thing is off or unavailable, so they read as
	  // a prohibition rather than as the thing itself.
	  case "person.slash.fill":                 return "🚫"
	  case "video.slash.fill":                  return "🚫"
	  case "waveform":                          return "🎵"
	  case "squareshape.split.3x3":             return "▦"
	  // Subject tiles (TeacherSubjectsViewModel), which reach here through
	  // SubjectChip/FlatIconTile rather than a literal at the call site.
	  case "angle":                             return "📐"
	  case "chart.pie":                         return "📊"
	  case "chart.xyaxis.line":                 return "📈"
	  case "gearshape.2":                       return "⚙"
	  case "waveform.path.ecg":                 return "〰"
	  case "chevron.left.forwardslash.chevron.right": return "</>"
	  case "list.bullet":                       return "☰"
	  // Form fields, settings rows and payout details — all of which render
	  // their icon via AuthInputField / FlatIconTile, and so land here too.
	  case "number":                            return "#"
	  case "key.fill":                          return "🔑"
	  case "slider.horizontal.3":               return "🎚"
	  case "creditcard":                        return "💳"
	  case "banknote":                          return "💵"
	  case "lock.fill":                         return "🔒"
	  case "rectangle.portrait.and.arrow.right":return "↪"
	  case "trash.fill":                        return "🗑"
	  case "banknote.fill":                     return "💵"
	  case "creditcard.fill":                   return "💳"
	  case "shield.lefthalf.filled":            return "🛡"
	  case "doc.text.fill":                     return "📄"
	  case "clock.fill":                        return "🕒"
	  case "clock":								return "⏰"
	  case "dollarsign.circle.fill":            return "$"
	  case "dollarsign.circle":            return "$"
	  // Currency-sign tab icons. Android has no SF Symbols, so each currency
	  // the Earnings tab can wear (see LessonFormatting.currencySignSymbolName)
	  // needs its sign here — an unmapped name falls through to a black dot.
	  case "shekelsign.circle.fill":            return "₪"
	  case "shekelsign.circle":                 return "₪"
	  case "eurosign.circle.fill":              return "€"
	  case "eurosign.circle":                   return "€"
	  case "sterlingsign.circle.fill":          return "£"
	  case "sterlingsign.circle":               return "£"
	  case "person.fill.checkmark":             return "✓"
	  case "bubble.left.and.bubble.right.fill": return "💬"
	  case "house":                             return "⌂"
	  case "house.fill":                        return "⌂"
	  case "person.fill":                       return "👤"
	  case "gearshape":                         return "⚙"
	  case "gearshape.fill":                    return "⚙"
	  case "play.fill":                         return "▶"
	  case "pause.fill":                        return "Ⅱ"
	  case "function":                          return "ƒ"
	  case "magnifyingglass":                   return "⌕"
	  case "arrow.up":                          return "↑"
	  case "arrow.right":						return "➡"
	  case "arrow.left":						return "←"
	  case "person.crop.circle.fill":           return "👤"
	  case "xmark":                             return "✕"
	  case "wifi":                              return "🛜"
	  case "camera.fill":                       return "📸"
	  case "star.fill":                         return "⭐"
	  case "pencil":                            return "✏️"
	  case "atom":                              return "⚛️"
	  case "x.squareroot":                      return "√"
	  case "phone":                             return "📞"
	  case "chevron.down":                      return "🔽"
	  case "chevron.left":						return "<"
	  case "chevron.right":                     return ">"
	  case "person":                            return "👤"
	  case "desktopcomputer":                   return "🖥️"
	  case "person.text.rectangle": 			return "🗂️"
	  case "icloud.and.arrow.up.fill":			return "☁️"
	  case "paperplane.fill":					return "📩"
	  case "bubble.left.fill":                  return "💬"
	  case "pin.fill":                          return "📍"
	  case "square":                           	return "□"
	  case "graduationcap.fill":				return "🎓"
	  case "envelope":                          return "📧"
	  case "eye.slash":							return "👁"
	  case "g.circle.fill":						return "G"
	  case "building.columns.fill":				return "🏰"
	  case "lightbulb.fill":					return "💡"
	  case "checkmark":							return "✓"
	  case "envelope.fill":						return "📧"
	  case "envelope.open.fill":                return "📬"
	  case "phone.fill":						return "📞"
	  case "globe":                             return "🌍"
	  case "p.circle.fill":                     return "P"
	  case "doc.plaintext.fill":				return "txt"
	  case "hand.raised.fill":					return "✋"
	  case "clock.badge.checkmark.fill":		return "⏰"
	  case "pencil.and.list.clipboard":			return "📝"
	  case "person.crop.rectangle":				return "👤"
	  case "arrow.left.arrow.right":            return "↔"
	  case "books.vertical.fill":               return "📚"
	  case "ruler.fill":                        return "📐"
	  case "bolt.fill":                         return "⚡"
	  case "testtube.2":                        return "🧪"
	  case "chart.bar.fill":                    return "📊"
	  case "laptopcomputer":                    return "💻"
	  case "leaf.fill":                         return "🌿"
	  case "triangle":							return "▲"
	  case "circle":							return "○"
	  case "line.diagonal":						return "╱"
	  case "trash":								return "🗑"
	  case "arrow.up.arrow.down": 				return "↕"
		
	  default:
		logger.error("!!! icon: \(systemName) is missing !!!")
		return "●"
	}
  }
}
