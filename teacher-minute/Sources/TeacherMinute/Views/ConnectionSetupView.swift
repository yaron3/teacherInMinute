import SwiftUI

struct ConnectionSetupView: View {
  let participantName: String
  let hasAudio: Bool
  var footerText = "Your teacher will join shortly"
  let onCancel: @MainActor @Sendable () -> Void
  @State var capsuleRotation = -18.0

  var connectionTitle: String {
    hasAudio ? "Connecting\naudio" : "Connecting"
  }

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 34)

      avatarSection

      connectionCard
        .padding(.horizontal, 16)
        .padding(.top, 42)

      if hasAudio {
        microphonePermissionCard
          .padding(.horizontal, 16)
          .padding(.top, 16)
      }

      Spacer()

      Text(footerText)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Color.appSecondaryText)

      Button(action: onCancel) {
        Text("Cancel Session")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Color.appPink)
          .frame(height: 36)
      }
      .buttonStyle(.plain)
      .padding(.bottom, 36)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      LinearGradient(
        colors: [Color.appCardBackground, Color.appPinkSoft.opacity(0.35), Color.appCardBackground],
        startPoint: .top,
        endPoint: .bottom
      )
    )
  }

  var avatarSection: some View {
    VStack(spacing: 14) {
      Circle()
        .fill(Color.appGrayBackground)
        .frame(width: 70, height: 70)
        .overlay {
          PlatformIcon(systemName: "person.crop.circle.fill", size: 62, color: .appSecondaryText)
        }
        .overlay {
          Circle().stroke(.white, lineWidth: 4)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 5)

      Text(participantName)
        .font(.system(size: 20, weight: .bold))
        .foregroundStyle(Color.appPrimaryText)

      HStack(spacing: 4) {
        ForEach(0..<5, id: \.self) { _ in
          PlatformIcon(systemName: "star.fill", size: 11, weight: .bold, color: .yellow)
        }
        Text("4.9")
          .font(.system(size: 11, weight: .bold))
          .foregroundStyle(Color.appPrimaryText)
        Text("(127 reviews)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.appSecondaryText)
      }
    }
  }

  var connectionCard: some View {
    HStack(spacing: 22) {
      Capsule()
        .fill(
          LinearGradient(
            colors: [Color.appPink, Color.appPurple],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .frame(width: 62, height: 104)
        .rotationEffect(.degrees(capsuleRotation))
        .overlay {
          PlatformIcon(systemName: "wifi", size: 20, weight: .bold, color: .white)
        }
        .task {
          withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            capsuleRotation = 342.0
          }
        }

      Spacer()

      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 8) {
          Text(connectionTitle)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(Color.appPrimaryText)
            .lineLimit(2)

          LoadingDotsView()
            .padding(.top, 7)
        }

        Text("Setting up your session")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(Color.appSecondaryText)

        GeometryReader { proxy in
          ZStack(alignment: .leading) {
            Capsule()
              .fill(Color.appGrayBackground)
            Capsule()
              .fill(
                LinearGradient(
                  colors: [Color.appPink, Color.appPurple],
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
    .background(Color.appCardBackground)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  var microphonePermissionCard: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Circle()
          .fill(Color.appOrange.opacity(0.12))
          .frame(width: 34, height: 34)
          .overlay {
            PlatformIcon(systemName: "mic.fill", size: 14, weight: .semibold, color: .appOrange)
          }

        VStack(alignment: .leading, spacing: 6) {
          Text("Microphone Permission")
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.appPrimaryText)
          Text("Make sure your microphone is enabled for the best learning experience.")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.appSecondaryText)
            .lineSpacing(3)
        }
      }

      Button {} label: {
        HStack(spacing: 8) {
          PlatformIcon(systemName: "checkmark", size: 11, weight: .bold, color: .white)
          Text("Allow Microphone")
            .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .background(Color.appOrange)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      }
      .buttonStyle(.plain)
      .padding(.leading, 52)
    }
    .padding(16)
    .background(Color.appOrange.opacity(0.06))
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(Color.appOrange.opacity(0.28), lineWidth: 1)
    }
  }
}

struct LoadingDotsView: View {
  @State var phase = 0

  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<2, id: \.self) { index in
        Circle()
          .fill(Color.appPrimaryText)
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
