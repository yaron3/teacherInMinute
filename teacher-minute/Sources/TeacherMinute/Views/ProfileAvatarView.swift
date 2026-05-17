import SwiftUI

#if os(iOS)
import UIKit
#endif

struct ProfileAvatarView: View {
    let imageURL: String
    let size: CGFloat
    let fallbackSystemImage: String
    let background: Color
    let tint: Color

    @Environment(\.colorScheme) var colorScheme

#if os(iOS)
    @State private var image: UIImage?
    @State private var loadedURL = ""
#endif

    var body: some View {
#if os(iOS)
        avatarContent
            .frame(width: size, height: size)
            .clipShape(Circle())
            .task(id: cacheKey) {
                loadedURL = imageURL
                image = await ProfileImageCache.shared.image(for: imageURL, pointSize: size)
            }
            .onChange(of: imageURL) { _, newValue in
                guard newValue != loadedURL else { return }
                image = nil
            }
#else
        avatarContent
            .frame(width: size, height: size)
            .clipShape(Circle())
#endif
    }

    @ViewBuilder
    private var avatarContent: some View {
#if os(iOS)
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            fallbackAvatar
        }
#else
        if let url = URL(string: imageURL), !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    fallbackAvatar
                }
            }
        } else {
            fallbackAvatar
        }
#endif
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(background)
            .overlay {
                PlatformIcon(
                    systemName: fallbackSystemImage,
                    size: max(14, size * 0.55),
                    weight: .semibold,
                    color: tint
                )
            }
    }

    private var cacheKey: String {
        "\(imageURL)|\(Int(size.rounded()))"
    }
}

#if os(iOS)
@MainActor
private final class ProfileImageCache {
    static let shared = ProfileImageCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL

    private init() {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        cacheDirectory = base.appendingPathComponent("ProfileImageCache", isDirectory: true)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func image(for urlString: String, pointSize: CGFloat) async -> UIImage? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed) else { return nil }

        let pixelSize = max(24, Int((pointSize * UIScreen.main.scale).rounded()))
        let fileURL = cacheDirectory.appendingPathComponent("\(stableHash(trimmed))-\(pixelSize).jpg")
        if let cached = UIImage(contentsOfFile: fileURL.path) {
            return cached
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data),
                  let resizedData = image.resizedJPEGData(maxPixelSize: pixelSize),
                  let resizedImage = UIImage(data: resizedData) else {
                return UIImage(data: data)
            }
            try resizedData.write(to: fileURL, options: [.atomic])
            return resizedImage
        } catch {
            return nil
        }
    }

    private func stableHash(_ value: String) -> String {
        var hash: UInt64 = 5381
        for scalar in value.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return String(hash, radix: 16)
    }
}

extension UIImage {
    func resizedJPEGData(maxPixelSize: Int, compressionQuality: CGFloat = 0.78) -> Data? {
        let longestSide = max(size.width, size.height)
        guard longestSide > 0 else { return jpegData(compressionQuality: compressionQuality) }

        let scale = min(1, CGFloat(maxPixelSize) / longestSide)
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: compressionQuality)
    }
}
#endif
