import SwiftUI
#if os(iOS)
import UIKit
#endif

struct CachedRemoteImage: View {
  let url: String
  let contentMode: ContentMode

#if os(iOS)
  @State var image: UIImage?
  @State var didFail = false
  @State var loadedURL = ""
#endif
  @Environment(\.colorScheme) var colorScheme
  var theme: AppTheme { AppTheme(colorScheme: colorScheme) }

  init(url: String, contentMode: ContentMode = .fit) {
    self.url = url
    self.contentMode = contentMode
  }

  var body: some View {
#if os(iOS)
    iOSContent
      .task(id: url) {
        await loadIfNeeded()
      }
#else
    androidContent
#endif
  }

#if os(iOS)
  @ViewBuilder
  private var iOSContent: some View {
    if let image {
      Image(uiImage: image)
        .resizable()
        .aspectRatio(contentMode: contentMode)
    } else if didFail {
      placeholder
    } else {
      ProgressView()
        .progressViewStyle(.circular)
        .tint(theme.appPrimaryText)
    }
  }

  private func loadIfNeeded() async {
    let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == loadedURL && image != nil { return }
    loadedURL = trimmed
    didFail = false
    image = nil
    guard !trimmed.isEmpty else { didFail = true; return }
    if let cached = await QuestionImageCache.shared.image(for: trimmed) {
      if trimmed == loadedURL { image = cached }
    } else if trimmed == loadedURL {
      didFail = true
    }
  }
#else
  @ViewBuilder
  private var androidContent: some View {
    if let imageURL = URL(string: url), !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      AsyncImage(url: imageURL) { phase in
        switch phase {
        case .success(let image):
          image
            .resizable()
            .aspectRatio(contentMode: contentMode)
        case .failure:
          placeholder
        default:
          ProgressView()
            .progressViewStyle(.circular)
            .tint(theme.appPrimaryText)
        }
      }
    } else {
      placeholder
    }
  }
#endif

  private var placeholder: some View {
    PlatformIcon(systemName: "photo.fill", size: 24, weight: .semibold, color: theme.appSecondaryText)
  }
}

#if os(iOS)
@MainActor
private final class QuestionImageCache {
  static let shared = QuestionImageCache()

  private let fileManager = FileManager.default
  private let cacheDirectory: URL
  private var memoryCache: [String: UIImage] = [:]
  private var inFlight: [String: Task<UIImage?, Never>] = [:]

  private init() {
    let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSTemporaryDirectory())
    cacheDirectory = base.appendingPathComponent("QuestionImageCache", isDirectory: true)
    try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
  }

  func image(for urlString: String) async -> UIImage? {
    let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }

    if let cached = memoryCache[trimmed] { return cached }

    let fileURL = cacheDirectory.appendingPathComponent("\(stableHash(trimmed)).jpg")
    if let cached = UIImage(contentsOfFile: fileURL.path) {
      memoryCache[trimmed] = cached
      return cached
    }

    if let existing = inFlight[trimmed] { return await existing.value }

    let task = Task<UIImage?, Never> { [fileURL] in
      do {
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else { return nil }
        try? data.write(to: fileURL, options: [.atomic])
        return image
      } catch {
        return nil
      }
    }
    inFlight[trimmed] = task
    let result = await task.value
    inFlight[trimmed] = nil
    if let result {
      memoryCache[trimmed] = result
    }
    return result
  }

  private func stableHash(_ value: String) -> String {
    var hash: UInt64 = 5381
    for scalar in value.unicodeScalars {
      hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
    }
    return String(hash, radix: 16)
  }
}
#endif
