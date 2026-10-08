//
//  LocalPhotoThumbnail.swift
//  teacher-minute
//
//  A photo the student has just taken or picked, drawn from its own bytes:
//  shown the moment it is taken, while it uploads, rather than once the
//  upload is done and the photo has come back down from its URL.
//

import SwiftUI
#if os(iOS)
import UIKit
#endif

struct LocalPhotoThumbnail: View {
  let data: Data
  /// The longer side the thumbnail is drawn at, in points.
  let maxPointSize: CGFloat

#if os(iOS)
  @State var image: UIImage?
  @Environment(\.displayScale) var displayScale
#else
  @State var fileURL: URL?
#endif

  var body: some View {
    content
      .task(id: data) {
        await load()
      }
  }

#if os(iOS)
  @ViewBuilder
  private var content: some View {
    if let image {
      Image(uiImage: image)
        .resizable()
        .aspectRatio(contentMode: .fill)
    } else {
      Color.clear
    }
  }

  /// Decoded at the thumbnail's own size, off the main thread: the photo
  /// itself is far larger than the tile it fills.
  private func load() async {
    let data = data
    let maxPixelSize = maxPointSize * displayScale
    let decoded = await Task.detached(priority: .userInitiated) {
      QuestionCamera.downsampled(data, maxPixelSize: maxPixelSize)
    }.value
    image = decoded.map { UIImage(cgImage: $0) }
  }
#else
  /// From a file, which Android's image loader decodes at the size it is
  /// drawn.
  @ViewBuilder
  private var content: some View {
    if let fileURL {
      AsyncImage(url: fileURL) { phase in
        if case .success(let image) = phase {
          image
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          Color.clear
        }
      }
    } else {
      Color.clear
    }
  }

  private func load() async {
    let data = data
    fileURL = await Task.detached(priority: .userInitiated) {
      QuestionCamera.previewFile(for: data)
    }.value
  }
#endif
}
