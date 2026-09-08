//
//  AndroidVideoFeed.swift
//  teacher-minute
//
//  SwiftUI wrappers around the Kotlin Compose-backed LiveKit video renderer.
//  Embed an `AndroidLiveKitVideoView` via Skip's `JavaBackedView` bridge so
//  the Android target can show the remote teacher feed and the student's
//  local preview inside the regular SwiftUI tree.
//

#if os(Android)
import SwiftUI
import SkipBridge

/// The remote participant's camera, with the student's own camera tucked into
/// its corner — the Android counterpart of `ChatSessionView.videoFeed`.
struct AndroidVideoFeed: View {
  let isStudent: Bool
  let isCameraOff: Bool
  let theme: AppTheme
  /// Handed down rather than localized here: views ask the view model for
  /// their strings, and this one is too far from it to hold one.
  let waitingForVideoText: String

  @State var remoteComposer: AndroidJavaObject?

  var body: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
      .fill(theme.videoBackground)
      .overlay {
        ZStack {
          remoteContent
          if isStudent {
            VStack {
              Spacer()
              HStack {
                Spacer()
                AndroidSelfVideoPreview(isCameraOff: isCameraOff, theme: theme)
              }
            }
            .padding(12)
          }
        }
      }
      // The renderer draws a live camera into this card, so the card has to be
      // the last word on where it may draw.
      .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      .task {
        if remoteComposer == nil {
          remoteComposer = try? AndroidLiveKitBridge.makeVideoComposer(mode: "remote", mirror: false)
        }
      }
  }

  @ViewBuilder
  private var remoteContent: some View {
    if let composer = remoteComposer,
       let backed = JavaBackedView(composer.toJavaObject(options: [.kotlincompat])) {
      backed
    } else {
      VStack(spacing: 10) {
        PlatformIcon(
          systemName: "video.fill",
          size: 32,
          weight: .semibold,
          color: theme.secondaryText
        )
        Text(waitingForVideoText)
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(theme.secondaryText)
      }
    }
  }
}

/// The local camera on its own, at the size the corner preview is drawn.
///
/// Kept apart from `AndroidVideoFeed` because the chat tab floats this over
/// the thread by itself: sizing the whole feed down to the preview's frame
/// would put the *other* participant in the window meant for you.
struct AndroidSelfVideoPreview: View {
  let isCameraOff: Bool
  let theme: AppTheme

  @State var localComposer: AndroidJavaObject?

  var body: some View {
    Group {
      if !isCameraOff,
         let composer = localComposer,
         let backed = JavaBackedView(composer.toJavaObject(options: [.kotlincompat])) {
        backed
      } else {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(theme.videoBackground.opacity(0.6))
          .overlay {
            PlatformIcon(
              systemName: isCameraOff ? "video.slash.fill" : "video.fill",
              size: 18,
              weight: .semibold,
              color: theme.onDarkFill
            )
          }
      }
    }
    .frame(width: 96, height: 132)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(theme.onDarkFill.opacity(0.4), lineWidth: 1)
    }
    .task {
      if localComposer == nil {
        localComposer = try? AndroidLiveKitBridge.makeVideoComposer(mode: "local", mirror: true)
      }
    }
  }
}
#endif
