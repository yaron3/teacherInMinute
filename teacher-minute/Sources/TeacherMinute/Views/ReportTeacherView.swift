//
//  ReportTeacherView.swift
//  teacher-minute
//
//  Reporting or blocking the teacher of a lesson. It covers whatever screen
//  opened it — the lesson, the rating after it, or the lesson in Activity —
//  and hands back, through its view model, whether the teacher is now
//  blocked.
//

import SwiftUI

struct ReportTeacherView: View {
  @State var viewModel: ReportTeacherViewModel

  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(viewModel: ReportTeacherViewModel) {
    _viewModel = State(initialValue: viewModel)
  }

  var body: some View {
    ZStack {
      BrandScreenBackground()
      VStack(spacing: 0) {
        BrandPageHeader(label: "", title: viewModel.title) {
          BrandCloseButton(accessibilityLabel: viewModel.closeLabel) {
            viewModel.close()
          }
          .accessibilityIdentifier("report_teacher_close")
        }
        if case .done(let blocked) = viewModel.phase {
          doneContent(blocked: blocked)
        } else {
          formContent
        }
      }
    }
    .trackScreen(AnalyticsScreen.reportTeacher)
    .onAppear { viewModel.appeared() }
    .appDialog(
      viewModel.blockConfirmTitle,
      isPresented: $viewModel.isConfirmingBlockOnly,
      message: viewModel.blockConfirmMessage,
      actions: [
        AppDialogAction(viewModel.cancelLabel, kind: .cancel),
        AppDialogAction(viewModel.blockLabel, kind: .destructive) {
          Task { await viewModel.blockOnly() }
        },
      ]
    )
  }

  // MARK: Form

  var formContent: some View {
    VStack(spacing: 0) {
      ScrollView(.vertical, showsIndicators: false) {
        VStack(alignment: .leading, spacing: 16) {
          Text(viewModel.reasonTitle)
            .font(.system(size: 17, weight: .bold))
            .foregroundStyle(theme.onDarkFill)
          reasonList
          detailsField
          alsoBlockRow
          Text(viewModel.reviewPromise)
            .font(.system(size: 12))
            .foregroundStyle(theme.brandMutedText)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      formButtons
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }
  }

  var reasonList: some View {
    VStack(spacing: 8) {
      ForEach(TeacherReportReason.allCases, id: \.self) { reason in
        reasonRow(reason)
      }
    }
  }

  func reasonRow(_ reason: TeacherReportReason) -> some View {
    let isSelected = viewModel.reason == reason
    return Button {
      viewModel.reason = reason
    } label: {
      HStack(spacing: 12) {
        Image(decorative: isSelected ? "home-choice-on" : "home-choice-off", bundle: .module)
          .resizable()
          .frame(width: 22, height: 22)
        Text(viewModel.label(for: reason))
          .font(.system(size: 15, weight: isSelected ? .bold : .medium))
          .foregroundStyle(theme.onDarkFill)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .background(isSelected ? theme.brandActionBackground.opacity(0.12) : theme.brandCardSurface)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(isSelected ? theme.brandActionBackground : theme.brandControlBorder, lineWidth: 1)
      }
      .tappableFrame()
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("report_reason_\(reason.rawValue)")
  }

  var detailsField: some View {
    TextEditor(text: $viewModel.details)
      .textInputAutocapitalization(.sentences)
      .font(.system(size: 15))
      .foregroundStyle(theme.onDarkFill)
      .tint(theme.brandActionBackground)
      .scrollContentBackground(.hidden)
      .padding(10)
      .frame(minHeight: 96, alignment: .leading)
      .background(theme.brandCardSurface)
      .clipShape(RoundedRectangle(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .stroke(theme.brandControlBorder, lineWidth: 1)
      }
      .overlay(alignment: .topLeading) {
        if viewModel.details.isEmpty {
          Text(viewModel.detailsPlaceholder)
            .font(.system(size: 15))
            .foregroundStyle(theme.brandMutedText)
            .padding(.horizontal, 15)
            .padding(.vertical, 18)
            .allowsHitTesting(false)
        }
      }
      .accessibilityIdentifier("report_details")
  }

  var alsoBlockRow: some View {
    HStack(alignment: .top, spacing: 12) {
      BrandCheckbox(isOn: $viewModel.alsoBlock)
        .accessibilityIdentifier("report_also_block")
      VStack(alignment: .leading, spacing: 4) {
        Text(viewModel.alsoBlockLabel)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(theme.onDarkFill)
        Text(viewModel.blockExplanation)
          .font(.system(size: 13))
          .foregroundStyle(theme.brandSecondaryText)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  var formButtons: some View {
    VStack(spacing: 10) {
      // Here rather than in the form, which may be scrolled past it.
      if let errorMessage = viewModel.errorMessage {
        Text(errorMessage)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(theme.brandDestructive)
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
      }
      BrandPrimaryButton(
        title: viewModel.sendReportLabel,
        isLoading: viewModel.isSending,
        isEnabled: viewModel.canSendReport
      ) {
        Task { await viewModel.sendReport() }
      }
      .accessibilityIdentifier("report_send")

      Button {
        viewModel.requestBlockOnly()
      } label: {
        Text(viewModel.blockOnlyLabel)
          .font(.system(size: 15, weight: .bold))
          .foregroundStyle(theme.brandDestructive)
          .multilineTextAlignment(.center)
          .frame(maxWidth: .infinity, minHeight: 44)
          .tappableFrame()
      }
      .buttonStyle(.plain)
      .disabled(viewModel.isSending)
      .accessibilityIdentifier("report_block_only")
    }
  }

  // MARK: Done

  func doneContent(blocked: Bool) -> some View {
    VStack(spacing: 18) {
      Spacer(minLength: 0)
      Image("brand-check-circle", bundle: .module)
        .renderingMode(.template)
        .resizable()
        .foregroundStyle(theme.brandSuccess)
        .frame(width: 64, height: 64)
      Text(viewModel.doneTitle)
        .font(.system(size: 24, weight: .bold))
        .foregroundStyle(theme.onDarkFill)
      Text(viewModel.doneMessage(blocked: blocked))
        .font(.system(size: 16, weight: .medium))
        .foregroundStyle(theme.brandSecondaryText)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      BrandPrimaryButton(title: viewModel.doneLabel) {
        viewModel.close()
      }
      .accessibilityIdentifier("report_done")
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 16)
  }
}
