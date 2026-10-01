//
//  LessonFormatting.swift
//  teacher-minute
//

import Foundation

enum LessonFormatting {
  static let defaultCurrencyCode = "ILS"
  
  static func relativeDateText(_ date: Date) -> String {
	guard date > Date.distantPast else {
	  return LocalizationSupport.localized("Recently")
	}
	
	let calendar = Calendar.current
	if calendar.isDateInToday(date) {
	  let formatter = DateFormatter()
	  formatter.locale = LocalizationSupport.currentLocale
	  formatter.dateStyle = .none
	  formatter.timeStyle = .short
	  return "\(LocalizationSupport.localized("Today")), \(formatter.string(from: date))"
	}
	if calendar.isDateInYesterday(date) {
	  return LocalizationSupport.localized("Yesterday")
	}
	
	let formatter = DateFormatter()
	formatter.dateFormat = "MMM d"
	return formatter.string(from: date)
  }
  
  /// A lesson's length to the second, as "m:ss": its time from the two sides
  /// connecting to the first of them ending it, as the backend settled it —
  /// the same the lesson's own timer ended on. Never rounded: what the lesson
  /// was charged is the backend's to decide (billedMinutes in
  /// functions/src/billing.ts), and shows as its amount.
  static func durationText(seconds: Int) -> String {
	let total = max(0, seconds)
	return String(format: "%d:%02d", total / 60, total % 60)
  }
  
  static func currencyText(cents: Int, currencyCode: String = defaultCurrencyCode) -> String {
	let amount = Double(cents) / 100.0
	let isWholeAmount = cents % 100 == 0
	if shouldPlaceCurrencySymbolAfterAmount(currencyCode: currencyCode) {
	  return "\(numberText(amount: amount, maximumFractionDigits: isWholeAmount ? 0 : 2))\(currencySymbol(for: currencyCode))"
	}
	
	let formatter = NumberFormatter()
	formatter.numberStyle = .currency
	formatter.currencyCode = currencyCode
	formatter.locale = LocalizationSupport.currentLocale
	formatter.maximumFractionDigits = isWholeAmount ? 0 : 2
	return formatter.string(from: NSNumber(value: amount)) ?? "\(currencyCode) \(String(format: "%.2f", amount))"
  }
  
  private static func numberText(amount: Double, maximumFractionDigits: Int) -> String {
	let formatter = NumberFormatter()
	formatter.numberStyle = .decimal
	formatter.locale = LocalizationSupport.currentLocale
	formatter.maximumFractionDigits = maximumFractionDigits
	formatter.minimumFractionDigits = 0
	return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.\(maximumFractionDigits)f", amount)
  }
  
  private static func shouldPlaceCurrencySymbolAfterAmount(currencyCode: String) -> Bool {
	currencyCode.uppercased() == "ILS" || LocalizationSupport.layoutDirection == .rightToLeft
  }
  
  /// The SF Symbol *stem* for a currency's sign — "shekelsign", "dollarsign".
  /// Unknown codes keep the dollar sign, which is what every currency-marked
  /// icon in the app used before this existed.
  static func currencySignSymbolName(for currencyCode: String) -> String {
	switch currencyCode.uppercased() {
	  case "ILS": return "shekelsign"
	  case "USD": return "dollarsign"
	  case "EUR": return "eurosign"
	  case "GBP": return "sterlingsign"
	  default: return "dollarsign"
	}
  }

  /// The app currency's sign, circled — for anywhere the UI marks a figure as
  /// money. Every such icon should come from here rather than naming a
  /// currency directly, so none of them can go on claiming dollars.
  /// `defaultCurrencyCode` is the app's currency (Settings fixes it to ILS);
  /// when that becomes a per-user choice, this is the single place to change.
  static var currencySignIcon: String {
	currencySignSymbolName(for: defaultCurrencyCode) + ".circle"
  }

  static var currencySignIconFilled: String {
	currencySignIcon + ".fill"
  }

  private static func currencySymbol(for currencyCode: String) -> String {
	if currencyCode.uppercased() == "ILS" {
	  return "₪"
	}
	
	let formatter = NumberFormatter()
	formatter.numberStyle = .currency
	formatter.currencyCode = currencyCode
	formatter.locale = LocalizationSupport.currentLocale
	return formatter.currencySymbol ?? currencyCode
  }
  
  /// The lessons' own times, to the second, summed and shown in whole minutes:
  /// never rounded up.
  /// The minutes a lesson of `seconds` is charged, counted as the backend's
  /// `billedMinutes` counts them: nothing under 30 seconds, then whole
  /// minutes, with a part-minute of more than 30 seconds counting as one.
  static func billedMinutes(seconds: Int) -> Int {
	guard seconds >= 30 else { return 0 }
	return max(1, seconds / 60 + (seconds % 60 > 30 ? 1 : 0))
  }

  static func totalDurationText(lessons: [HistoryLesson]) -> String {
	let totalSeconds = lessons.reduce(0) { $0 + max(0, $1.durationSeconds) }
	return minutesText(totalSeconds / 60)
  }
  
  static func minutesText(_ minutes: Int) -> String {
	let displayMinutes = max(0, minutes)
	if displayMinutes == 0 { return String(format: LocalizationSupport.localized("%d min"), 0) }
	return displayMinutes == 1
	? LocalizationSupport.localized("1 min")
	: String(format: LocalizationSupport.localized("%d min"), displayMinutes)
  }
  
  static func totalCostText(lessons: [HistoryLesson], currencyCode: String? = nil) -> String {
	let totalCents = lessons.reduce(0) { $0 + $1.costCents }
	let displayCurrencyCode = currencyCode ?? lessons.first?.currencyCode ?? defaultCurrencyCode
	return currencyText(cents: totalCents, currencyCode: displayCurrencyCode)
  }

  // MARK: - Ratings

  /// A star average as one decimal in the viewer's locale — "4.9" in English,
  /// where a locale using a decimal comma writes "4,9".
  static func ratingText(_ rating: Double) -> String {
	numberText(amount: rating, maximumFractionDigits: 1)
  }

  /// "(1 review)" / "(12 reviews)". Returns an empty string when there are no
  /// reviews, so callers can hide the label rather than print "(0 reviews)".
  static func reviewCountText(_ count: Int) -> String {
	guard count > 0 else { return "" }
	return count == 1
	? LocalizationSupport.localized("(1 review)")
	: String(format: LocalizationSupport.localized("(%d reviews)"), count)
  }

  // MARK: - Connection time

  /// A measured connect time spelled out — "90 seconds", "2 minutes". Empty
  /// when there is no measurement, so callers can drop the claim rather than
  /// invent a number.
  static func connectDurationText(seconds: Int) -> String {
	guard seconds > 0 else { return "" }
	if seconds < 120 {
	  return String(format: LocalizationSupport.localized("%d seconds"), seconds)
	}
	let minutes = Int((Double(seconds) / 60.0).rounded())
	return String(format: LocalizationSupport.localized("%d minutes"), minutes)
  }

  /// The same figure abbreviated, for tight rows — "90 sec", "2 min".
  static func connectDurationShortText(seconds: Int) -> String {
	guard seconds > 0 else { return "" }
	if seconds < 120 {
	  return String(format: LocalizationSupport.localized("%d sec"), seconds)
	}
	let minutes = Int((Double(seconds) / 60.0).rounded())
	return String(format: LocalizationSupport.localized("%d min"), minutes)
  }

  /// How long students currently wait to be connected, e.g. "90 sec avg to
  /// connect". Measured by the backend (functions/src/stats.ts) — never a
  /// fixed claim — so callers pass 0 when there is no measurement yet.
  static func averageConnectText(seconds: Int) -> String {
	let duration = connectDurationShortText(seconds: seconds)
	guard !duration.isEmpty else { return "" }
	return String(format: LocalizationSupport.localized("%@ avg to connect"), duration)
  }

  // MARK: - Calendar months

  /// The standalone month name in the viewer's language — "August" in English,
  /// "אוגוסט" in Hebrew. Comes from the locale's own calendar symbols rather
  /// than a hand-maintained table, so it follows the app's language setting.
  static func monthName(month: Int) -> String {
	guard month >= 1, month <= 12 else { return "\(month)" }
	let formatter = DateFormatter()
	formatter.locale = LocalizationSupport.currentLocale
	let symbols: [String]? = formatter.standaloneMonthSymbols
	guard let symbols, symbols.count == 12 else { return "\(month)" }
	return symbols[month - 1]
  }

  /// "August 2026" / "אוגוסט 2026".
  static func monthYearText(year: Int, month: Int) -> String {
	String(format: LocalizationSupport.localized("%@ %d"), monthName(month: month), year)
  }

  /// A calendar date in the viewer's locale — used for the payout date.
  static func dateText(_ date: Date) -> String {
	let formatter = DateFormatter()
	formatter.locale = LocalizationSupport.currentLocale
	formatter.dateStyle = .medium
	formatter.timeStyle = .none
	return formatter.string(from: date)
  }
}
