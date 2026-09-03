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
  /// Optional free text. The teacher reads it later without knowing who wrote
  /// it, which is what the placeholder promises.
  @State var comment: String = ""
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
            .foregroundStyle(theme.secondaryText)
            .frame(width: 36, height: 36)
            .background(theme.cardBackground)
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
              colors: [theme.accent, theme.accentStrong],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ))
            .frame(width: 72, height: 72)
            .overlay {
              PlatformIcon(systemName: "checkmark")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(theme.onDarkFill)
            }
            .padding(.top, 8)

          VStack(spacing: 6) {
            Text(LocalizationSupport.localized("Session Complete!"))
              .font(.system(size: 22, weight: .bold))
              .foregroundStyle(theme.primaryText)
            Text(String(
              format: LocalizationSupport.localized("Great job learning with %@"),
              teacherName
            ))
              .font(.system(size: 14))
              .foregroundStyle(theme.secondaryText)
              .multilineTextAlignment(.center)
          }

          RoundedInfoCard {
            HStack(spacing: 14) {
              ProfileAvatarView(
                imageURL: teacherImageURL,
                size: 56,
                fallbackSystemImage: "person.fill",
                background: theme.accentBackground,
                tint: theme.accent
              )
              VStack(alignment: .leading, spacing: 4) {
                Text(teacherName)
                  .font(.system(size: 16, weight: .bold))
                  .foregroundStyle(theme.primaryText)
                if !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                  Text(subject)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.secondaryText)
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
                .foregroundStyle(theme.primaryText)
              Text(String(
                format: LocalizationSupport.localized("How was your experience with %@?"),
                teacherName
              ))
                .font(.system(size: 13))
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
              HStack(spacing: 10) {
                ForEach(1..<6, id: \.self) { index in
                  Button {
                    rating = index
                  } label: {
                    PlatformIcon(systemName: index <= rating ? "star.fill" : "star")
                      .font(.system(size: 32, weight: .bold))
                      .foregroundStyle(index <= rating ? theme.ratingStar : theme.secondaryText)
                  }
                  .buttonStyle(.plain)
                }
              }

              // The box appears only once a score is picked: with no stars
              // chosen the Send button is disabled anyway, so an empty text
              // field would just be dead space above it.
              if rating > 0 {
                VStack(alignment: .leading, spacing: 6) {
                  TextEditor(text: $comment)
                    .textInputAutocapitalization(.sentences)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(theme.primaryText)
                    .tint(theme.accent)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 88, alignment: .leading)
                    .background(theme.fieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // The card behind it is already a light fill, so without a
                    // border the field does not read as somewhere to type.
                    .overlay {
                      RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.controlBorder, lineWidth: 1)
                    }
                    .overlay(alignment: .topLeading) {
                      if comment.isEmpty {
                        Text(LocalizationSupport.localized("Add a comment (optional)"))
                          .font(.system(size: 14))
                          .foregroundStyle(theme.secondaryText)
                          .padding(.horizontal, 15)
                          .padding(.vertical, 18)
                          .allowsHitTesting(false)
                      }
                    }

                  Text(LocalizationSupport.localized("Your teacher sees this without your name."))
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
              }
            }
            .frame(maxWidth: .infinity)
          }

          if let errorMessage {
            Text(errorMessage)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(theme.danger)
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
              .tint(theme.onDarkFill)
          } else {
            Text(LocalizationSupport.localized("Send"))
              .font(.system(size: 16, weight: .bold))
              .foregroundStyle(theme.onDarkFill)
          }
          Spacer()
        }
        .frame(height: 52)
        .background(
          LinearGradient(
            colors: rating > 0 ? [theme.accent, theme.accentStrong] : [theme.secondaryText, theme.secondaryText],
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
        errorMessage = LocalizationSupport.localized("Could not send rating. Please try again next time.")
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
          rating: rating,
          comment: comment
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
