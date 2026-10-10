//
//  BlockedTeachersSection.swift
//  teacher-minute
//
//  The student's blocked teachers, as a card on the Privacy Controls page,
//  each with the way to unblock them.
//

import SwiftUI

struct BlockedTeachersSection: View {
  @State var viewModel = BlockedTeachersViewModel()

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(viewModel.sectionTitle)
        .font(.system(size: 17, weight: .bold))
        .foregroundStyle(theme.brandSecondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
      content
      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.brandDestructive)
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(viewModel.footerText)
        .font(.system(size: 13))
        .foregroundStyle(theme.brandSecondaryText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .brandCard()
    .task { await viewModel.load() }
  }

  @ViewBuilder
  var content: some View {
    if !viewModel.hasLoaded {
      ProgressView()
        .tint(theme.onDarkFill)
        .frame(maxWidth: .infinity, minHeight: 52)
    } else if viewModel.showsEmptyState {
      Text(viewModel.emptyText)
        .font(.system(size: 15))
        .foregroundStyle(theme.onDarkFill)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    } else {
      VStack(spacing: 0) {
        ForEach(viewModel.teachers) { teacher in
          row(teacher)
        }
      }
    }
  }

  func row(_ teacher: BlockedTeacher) -> some View {
    HStack(spacing: 12) {
      Text(viewModel.displayName(for: teacher))
        .font(.system(size: 16))
        .foregroundStyle(theme.onDarkFill)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      if viewModel.unblockingUid == teacher.teacherUid {
        ProgressView()
          .tint(theme.onDarkFill)
          .frame(width: 80)
      } else {
        Button {
          Task { await viewModel.unblock(teacher) }
        } label: {
          Text(viewModel.unblockLabel)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.brandActionBackground)
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .overlay {
              RoundedRectangle(cornerRadius: 8)
                .stroke(theme.brandActionBackground, lineWidth: 1)
            }
            .tappableFrame()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("unblock_teacher_\(teacher.teacherUid)")
      }
    }
    .padding(.horizontal, 12)
    .frame(minHeight: 52)
  }
}
