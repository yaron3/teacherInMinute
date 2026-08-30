import SwiftUI

struct ConnectionSetupView: View {
  @State var viewModel: ConnectionSetupViewModel
  @State var capsuleRotation = -18.0
  let onCancel: @MainActor @Sendable () -> Void
  var onSessionStarted: (@MainActor @Sendable () -> Void)? = nil
  var onContinueAsText: (@MainActor @Sendable () -> Void)? = nil
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }

  init(
    participantName: String,
    participantTeacherId: String = "",
    conversationType: String,
    footerText: String = LocalizationSupport.localized("Your teacher will join shortly"),
    viewModel sessionViewModel: (any ChatSessionViewModeling)? = nil,
    liveKitRoom: String = "",
    liveKitToken: String = "",
    onCancel: @escaping @MainActor @Sendable () -> Void,
    onSessionStarted: (@MainActor @Sendable () -> Void)? = nil,
    onContinueAsText: (@MainActor @Sendable () -> Void)? = nil
  ) {
    self._viewModel = State(
      initialValue: ConnectionSetupViewModel(
        participantName: participantName,
        participantTeacherId: participantTeacherId,
        conversationType: conversationType,
        footerText: footerText,
        sessionViewModel: sessionViewModel,
        liveKitRoom: liveKitRoom,
        liveKitToken: liveKitToken,
        onSessionStarted: onSessionStarted
      )
    )
    self.onCancel = onCancel
    self.onSessionStarted = onSessionStarted
    self.onContinueAsText = onContinueAsText
  }

  var body: some View {
    ZStack {
      setupContent

      if viewModel.hasTimedOut {
        timeoutOverlay
      }
    }
    .task(id: viewModel.sessionStartKey) {
      await viewModel.runSetupAttempt()
    }
    .task(id: viewModel.timerKey) {
      await viewModel.startTimeoutTimer()
    }
    .task {
      await viewModel.loadParticipantRating()
    }
    .trackScreen(AnalyticsScreen.connectionSetup)
  }

  var setupContent: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 34)

      avatarSection

      connectionCard
        .padding(.horizontal, 16)
        .padding(.top, 42)

      if viewModel.hasAudio {
        microphonePermissionCard
          .padding(.horizontal, 16)
          .padding(.top, 16)
      }

      if viewModel.hasVideo {
        cameraPermissionCard
          .padding(.horizontal, 16)
          .padding(.top, 16)
      }

      Spacer()

      Text(viewModel.footerText)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(viewModel.statusTextColorNeedsAttention ? theme.warning : theme.secondaryText)

      Button(action: onCancel) {
        Text(LocalizationSupport.localized("Cancel Session"))
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(theme.accent)
          .frame(height: 36)
      }
      .buttonStyle(.plain)
      .padding(.bottom, 36)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      LinearGradient(
        colors: [theme.cardBackground, theme.accentBackground, theme.cardBackground],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  var timeoutOverlay: some View {
    ZStack {
      theme.scrim.opacity(0.45)
        .ignoresSafeArea()

      VStack(spacing: 18) {
        PlatformIcon(
          systemName: viewModel.hasVideo ? "video.slash.fill" : "mic.slash.fill",
          size: 28,
          weight: .semibold,
          color: theme.accent
        )
        .frame(width: 56, height: 56)
        .background(theme.accentBackground)
        .clipShape(Circle())

        Text(LocalizationSupport.localized("Connection is taking longer than usual"))
          .font(.system(size: 16, weight: .bold))
          .foregroundStyle(theme.primaryText)
          .multilineTextAlignment(.center)

        Text(
          viewModel.hasVideo
            ? LocalizationSupport.localized("We couldn't establish a video connection. Retry, continue with text only, or cancel.")
            : LocalizationSupport.localized("We couldn't establish an audio connection. Retry, continue with text only, or cancel.")
        )
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(viewModel.statusTextColorNeedsAttention ? theme.warning : theme.secondaryText)
        .multilineTextAlignment(.center)

        VStack(spacing: 10) {
          Button {
            viewModel.retry()
          } label: {
            Text(LocalizationSupport.localized("Retry"))
              .font(.system(size: 14, weight: .bold))
              .foregroundStyle(theme.onAccentText)
              .frame(maxWidth: .infinity)
              .frame(height: 44)
              .background(theme.accent)
              .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
          }
          .buttonStyle(.plain)

          if let onContinueAsText {
            Button {
              viewModel.continueAsText()
              onContinueAsText()
            } label: {
              Text(LocalizationSupport.localized("Continue with text only"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
          }

          Button(action: onCancel) {
            Text(LocalizationSupport.localized("Cancel"))
              .font(.system(size: 13, weight: .semibold))
              .foregroundStyle(theme.secondaryText)
              .frame(maxWidth: .infinity)
              .frame(height: 38)
          }
          .buttonStyle(.plain)
        }
      }
      .padding(24)
      .frame(maxWidth: 320)
      .background(theme.cardBackground)
      .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
      .shadow(color: theme.cardShadow.opacity(0.18), radius: 24, x: 0, y: 14)
      .padding(.horizontal, 24)
    }
  }

  var avatarSection: some View {
    VStack(spacing: 14) {
      Circle()
        .fill(theme.cardBackground)
        .frame(width: 70, height: 70)
        .overlay {
          PlatformIcon(systemName: "person.crop.circle.fill", size: 62, color: theme.secondaryText)
        }
        .overlay {
          Circle().stroke(theme.screenBackground, lineWidth: 4)
        }
        .shadow(color: theme.cardShadow.opacity(0.12), radius: 10, x: 0, y: 5)

      Text(viewModel.participantName)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(theme.primaryText)

      // Only shown once the teacher has actually been rated — the student is
      // told who is joining, not sold a score nobody gave.
      if viewModel.showsRating {
        RatingSummaryView(
          rating: viewModel.participantRating,
          reviewCount: viewModel.participantReviewCount
        )
      }
    }
  }

  var connectionCard: some View {
    VStack(spacing: 22) {
      Capsule()
        .fill(
          LinearGradient(
            colors: [theme.accent, theme.accentStrong],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .frame(width: 62, height: 104)
        .rotationEffect(.degrees(capsuleRotation))
        .overlay {
          PlatformIcon(systemName: "wifi", size: 20, weight: .bold, color: theme.onDarkFill)
        }
        .task {
          withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            capsuleRotation = 342.0
          }
        }

      Spacer()

      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 8) {
          Spacer()
          Text(viewModel.connectionTitle)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(theme.primaryText)
            .lineLimit(2)

          LoadingDotsView()
            .padding(.top, 7)
          Spacer()
        }
        HStack {
          Spacer()
          Text(viewModel.setupStatusText)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(viewModel.statusTextColorNeedsAttention ? theme.warning : theme.secondaryText)
            .multilineTextAlignment(.center)
          Spacer()
        }
        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(theme.cardBackground)
            Capsule()
              .fill(
                LinearGradient(
                  colors: [theme.accent, theme.accentStrong],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              )
              .frame(width: proxy.size.width * 0.66)
          }
        }
        .frame(height: 5)
        .padding(.top, 14)
      }

      Spacer(minLength: 0)
    }
    .padding(28)
    .frame(maxWidth: .infinity, minHeight: 132)
    .background(theme.cardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  var microphonePermissionCard: some View {
    permissionCard(
      icon: "mic.fill",
      title: LocalizationSupport.localized("Microphone Permission"),
      message: LocalizationSupport.localized("Make sure your microphone is enabled for the best learning experience."),
      buttonTitle: viewModel.microphoneButtonTitle,
      buttonIcon: viewModel.microphoneState.isGranted ? "checkmark" : "mic.fill"
    ) {
      viewModel.requestPermission(.microphone)
    }
  }

  var cameraPermissionCard: some View {
    permissionCard(
      icon: "video.fill",
      title: "Camera Permission",
      message: "Make sure your camera is enabled so your teacher can see your work.",
      buttonTitle: viewModel.cameraButtonTitle,
      buttonIcon: viewModel.cameraState.isGranted ? "checkmark" : "video.fill"
    ) {
      viewModel.requestPermission(.camera)
    }
  }

  func permissionCard(icon: String, title: String, message: String, buttonTitle: String, buttonIcon: String, action: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Circle()
          .fill(theme.warning.opacity(0.12))
          .frame(width: 34, height: 34)
          .overlay {
            PlatformIcon(systemName: icon, size: 14, weight: .semibold, color: theme.warning)
          }

        VStack(alignment: .leading, spacing: 6) {
          Text(LocalizationSupport.localized(title))
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(theme.primaryText)
          Text(LocalizationSupport.localized(message))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.secondaryText)
            .lineSpacing(3)
        }
      }

      Button(action: action) {
        HStack(spacing: 8) {
          PlatformIcon(systemName: buttonIcon, size: 11, weight: .bold, color: theme.onBrightFill)
          Text(buttonTitle)
            .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(theme.primaryText)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(theme.warning)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .buttonStyle(.plain)
      .padding(.leading, 52)
    }
    .padding(16)
    .background(theme.warning.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(theme.warning.opacity(0.28), lineWidth: 1)
    }
  }
}

struct LoadingDotsView: View {
  @State var phase = 0
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme {
    AppTheme(colorScheme: colorScheme)
  }
  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<3, id: \.self) { index in
        Circle()
          .fill(theme.secondaryText)
          .frame(width: 3, height: 3)
          .opacity(phase == index ? 1 : 0.28)
      }
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 420_000_000)
        phase = (phase + 1) % 2
      }
    }
  }
}

#if os(iOS)
#Preview {
  ConnectionSetupView(participantName: "Dono Gilroy", conversationType: "video", footerText: "This is a footer", onCancel: {})
}
#endif
