//
//  howItWorks.swift
//
//
//  Created by Yaron Jackoby on 02/09/2026.
//

import SwiftUI

struct HowItWorksPanel: View {
  let title: String
  let steps: [HowItWorksStep]
  let theme: AppTheme

  /// Accent per position, from the brand's palette. Every panel walks this
  /// same sequence and the shorter ones stop early, so the student's four
  /// steps and the teacher's three stay in step with each other.
  private var tints: [Color] {
    [theme.brandActionBackground, theme.brandSuccess, theme.brandOptionBorder, theme.warning]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text(title)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(spacing: 24) {
        ForEach(0..<steps.count, id: \.self) { index in
          howItWorksStep(steps[index], number: index + 1, tint: tints[index % tints.count])
        }
      }
    }
    .brandCard(padding: 22)
  }

  private func howItWorksStep(_ step: HowItWorksStep, number: Int, tint: Color) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Circle()
        .stroke(tint, lineWidth: 3)
        .frame(width: 46, height: 46)
        .overlay {
          Text("\(number)")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(tint)
        }

      VStack(alignment: .leading, spacing: 6) {
        Text(step.title)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .lineLimit(2)
          .minimumScaleFactor(0.82)

        Text(step.subtitle)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(theme.brandSecondaryText)
          .lineLimit(2)
          .minimumScaleFactor(0.82)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
