//
//  RatingStarsView.swift
//  teacher-minute
//
// The one place stars are drawn from a rating. Every screen that shows a
// teacher's reputation (dashboard, profile, connection setup, lesson history)
// renders through this, so a half-empty rating looks the same everywhere and no
// screen can quietly draw five filled stars regardless of the score.
//

import SwiftUI

struct RatingStarsView: View {
  /// 0–5. A rating of 0 draws five empty stars, which only happens when the
  /// caller has chosen to show the control for an unrated teacher.
  let rating: Double
  var size: CGFloat = 14
  var spacing: CGFloat = 2
  var filledColor: Color?
  var emptyColor: Color?

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

  var body: some View {
    HStack(spacing: spacing) {
      ForEach(0..<5, id: \.self) { index in
        let isFilled = Double(index) < rating
        PlatformIcon(
          systemName: isFilled ? "star.fill" : "star",
          size: size,
          weight: .bold,
          color: isFilled ? (filledColor ?? theme.ratingStar) : (emptyColor ?? theme.secondaryText)
        )
      }
    }
  }
}

/// Stars plus the numeric score and review count, the layout used wherever a
/// teacher is introduced to a student.
struct RatingSummaryView: View {
  let rating: Double
  let reviewCount: Int
  var starSize: CGFloat = 11
  var font: CGFloat = 11

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

  var body: some View {
    HStack(spacing: 4) {
      RatingStarsView(rating: rating, size: starSize)

      Text(LessonFormatting.ratingText(rating))
        .font(.system(size: font, weight: .bold))
        .foregroundStyle(theme.primaryText)

      let reviews = LessonFormatting.reviewCountText(reviewCount)
      if !reviews.isEmpty {
        Text(reviews)
          .font(.system(size: font, weight: .medium))
          .foregroundStyle(theme.secondaryText)
      }
    }
  }
}
