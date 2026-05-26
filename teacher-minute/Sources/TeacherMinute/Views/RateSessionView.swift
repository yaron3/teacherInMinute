import SwiftUI

struct RateSessionView: View {
  let teacherName: String
  let teacherImageURL: String
  let subject: String
  let teacherId: String
  let questionId: String
  let prepareForRating: @MainActor () async -> Void
  let onFinish: @MainActor () -> Void

  @State var rating: Int = 0
  @State var isSending = false
  @State var errorMessage: String?
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(
    teacherName: String,
    teacherImageURL: String,
    subject: String,
    teacherId: String,
    questionId: String,
    prepareForRating: @escaping @MainActor () async -> Void = {},
    onFinish: @escaping @MainActor () -> Void
  ) {
    self.teacherName = teacherName
    self.teacherImageURL = teacherImageURL
    self.subject = subject
    self.teacherId = teacherId
    self.questionId = questionId
    self.prepareForRating = prepareForRating
    self.onFinish = onFinish
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Spacer()
        Button(action: onFinish) {
          PlatformIcon(systemName: "xmark")
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(theme.appSecondaryText)
            .frame(width: 36, height: 36)
            .background(theme.appCardBackground)
            .clipShape(Circle())
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 18)
      .padding(.top, 12)

      ScrollView(.vertical, showsIndicators: false) {
        VStack(spacing: 20) {
          Circle()
            .fill(LinearGradient(
              colors: [theme.appPink, theme.appPurple],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ))
            .frame(width: 72, height: 72)
            .overlay {
              PlatformIcon(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
            }
            .padding(.top, 8)

          VStack(spacing: 6) {
            Text(LocalizationSupport.localized("Session Complete!"))
              .font(.system(size: 22, weight: .bold))
              .foregroundStyle(theme.appPrimaryText)
            Text(String(
              format: LocalizationSupport.localized("Great job learning with %@"),
              teacherName
            ))
              .font(.system(size: 14))
              .foregroundStyle(theme.appSecondaryText)
              .multilineTextAlignment(.center)
          }

          RoundedInfoCard {
            HStack(spacing: 14) {
              ProfileAvatarView(
                imageURL: teacherImageURL,
                size: 56,
                fallbackSystemImage: "person.fill",
                background: theme.appPinkSoft,
                tint: theme.appPink
              )
              VStack(alignment: .leading, spacing: 4) {
                Text(teacherName)
                  .font(.system(size: 16, weight: .bold))
                  .foregroundStyle(theme.appPrimaryText)
                if !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  Text(subject)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.appSecondaryText)
                    .lineLimit(2)
                }
              }
              Spacer()
            }
          }

          RoundedInfoCard {
            VStack(spacing: 14) {
              Text(LocalizationSupport.localized("Rate this session"))
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.appPrimaryText)
              Text(String(
                format: LocalizationSupport.localized("How was your experience with %@?"),
                teacherName
              ))
                .font(.system(size: 13))
                .foregroundStyle(theme.appSecondaryText)
                .multilineTextAlignment(.center)
              HStack(spacing: 10) {
                ForEach(1..<6, id: \.self) { index in
                  Button {
                    rating = index
                  } label: {
                    PlatformIcon(systemName: index <= rating ? "star.fill" : "star")
                      .font(.system(size: 32, weight: .bold))
                      .foregroundStyle(index <= rating ? theme.yellow : theme.appSecondaryText)
                  }
                  .buttonStyle(.plain)
                }
              }
            }
            .frame(maxWidth: .infinity)
          }

          if let errorMessage {
            Text(errorMessage)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(theme.red)
              .multilineTextAlignment(.center)
          }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
      }

      Button(action: send) {
        HStack {
          Spacer()
          if isSending {
            ProgressView()
              .tint(.white)
          } else {
            Text(LocalizationSupport.localized("Send"))
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(.white)
          }
          Spacer()
        }
        .frame(height: 52)
        .background(
          LinearGradient(
            colors: rating > 0 ? [theme.appPink, theme.appPurple] : [theme.appSecondaryText, theme.appSecondaryText],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(rating == 0 || isSending)
      .padding(.horizontal, 18)
      .padding(.bottom, 24)
    }
    .background(Color(.systemBackground))
  }

  private func send() {
    guard rating > 0, !isSending else { return }
    isSending = true
    errorMessage = nil
    Task {
      do {
        await prepareForRating()
        try await sendRatingWhenFinalized()
        isSending = false
        onFinish()
      } catch {
        isSending = false
        errorMessage = LocalizationSupport.localized("Could not send rating. Please try again.")
        logger.error("[RateSession] rateTeacher failed: \(error.localizedDescription)")
      }
    }
  }

  private func sendRatingWhenFinalized() async throws {
    for attempt in 0..<4 {
      do {
        try await FunctionsService.shared.rateTeacher(
          questionId: questionId,
          teacherId: teacherId,
          rating: rating
        )
        return
      } catch {
        guard error.isLessonFinalizingError, attempt < 3 else { throw error }
        try await Task.sleep(nanoseconds: 1_500_000_000)
      }
    }
  }
}

private extension Error {
  var isLessonFinalizingError: Bool {
    guard let functionError = self as? FunctionsError else { return false }
    if case .serverError(let message, let status) = functionError {
      return status == "FAILED_PRECONDITION"
        && message.localizedCaseInsensitiveContains("finaliz")
    }
    return false
  }
}
