//
//  AndroidVideoFeed.swift
//  teacher-minute
//
//  SwiftUI wrapper around the Kotlin Compose-backed LiveKit video renderer.
//  Embeds an `AndroidLiveKitVideoView` via Skip's `JavaBackedView` bridge so
//  the Android target can show the remote teacher feed and the student's
//  local preview inside the regular SwiftUI tree.
//

#if os(Android)
import SwiftUI
import SkipBridge

struct AndroidVideoFeed: View {
  let isStudent: Bool
  let isCameraOff: Bool
  let theme: AppTheme

  @State var remoteComposer: AndroidJavaObject?
  @State var localComposer: AndroidJavaObject?

  var body: some View {
    RoundedRectangle(cornerRadius: 18, style: .continuous)
      .fill(Color.black)
      .overlay {
        ZStack {
          remoteContent
          if isStudent {
            VStack {
              Spacer()
              HStack {
                Spacer()
                localPreview
              }
            }
            .padding(12)
          }
        }
      }
      .task {
        if remoteComposer == nil {
          remoteComposer = try? AndroidLiveKitBridge.makeVideoComposer(mode: "remote", mirror: false)
        }
        if isStudent, localComposer == nil {
          localComposer = try? AndroidLiveKitBridge.makeVideoComposer(mode: "local", mirror: true)
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
          color: theme.appSecondaryText
        )
        Text(LocalizationSupport.localized("Waiting for video…"))
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(theme.appSecondaryText)
      }
    }
  }

  @ViewBuilder
  private var localPreview: some View {
    Group {
      if !isCameraOff,
         let composer = localComposer,
         let backed = JavaBackedView(composer.toJavaObject(options: [.kotlincompat])) {
        backed
      } else {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
          .fill(Color.black.opacity(0.6))
          .overlay {
            PlatformIcon(
              systemName: isCameraOff ? "video.slash.fill" : "video.fill",
              size: 18,
              weight: .semibold,
              color: theme.white
            )
          }
      }
    }
    .frame(width: 96, height: 132)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(.white.opacity(0.4), lineWidth: 1)
    }
  }
}
#endif
