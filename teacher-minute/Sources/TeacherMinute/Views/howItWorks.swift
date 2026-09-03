//
//  howItWorks.swift
//
//
//  Created by Yaron Jackoby on 02/09/2026.
//

import SwiftUI

struct HowItWorksStep {
  let number: Int
  let title: String
  let subtitle: String
  let tint: Color
}

struct HowItWorksPanel: View {
  let title: String
  let steps: [HowItWorksStep]
  let theme: AppTheme

  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      Text(title)
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
        .frame(maxWidth: .infinity, alignment: .leading)

      VStack(spacing: 24) {
        ForEach(steps, id: \.number) { step in
          howItWorksStep(step)
        }
      }
    }
    .padding(22)
    .background(theme.accentStrong)
    .clipShape(RoundedRectangle(cornerRadius: flatRadius, style: .continuous))
  }

  private func howItWorksStep(_ step: HowItWorksStep) -> some View {
    HStack(alignment: .top, spacing: 16) {
      Circle()
        .stroke(step.tint, lineWidth: 3)
        .frame(width: 46, height: 46)
        .overlay {
          Text("\(step.number)")
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(step.tint)
        }

      VStack(alignment: .leading, spacing: 6) {
        Text(step.title)
          .font(.system(size: 18, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
          .lineLimit(2)
          .minimumScaleFactor(0.82)

        Text(step.subtitle)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(theme.onDarkFill.opacity(0.6))
          .lineLimit(2)
          .minimumScaleFactor(0.82)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
