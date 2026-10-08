import Foundation
#if os(iOS)
@preconcurrency import AVFoundation
import ImageIO
import UIKit
#elseif os(Android)
import SkipBridge
#endif

/// The back camera behind the student's home: a live preview
/// (`QuestionCameraPreview`), and a still of the question when the student
/// takes one.
///
/// The camera belongs to the preview. It runs while the preview is on screen
/// and stops when it leaves — the text tab, a lesson, another section — so it
/// is never held under a video lesson that needs it.
enum QuestionCamera {
  /// The longer side of an uploaded photo: enough to read a page of sums
  /// across a phone's screen, and a fraction of a full frame to capture,
  /// encode and upload.
  static let maxDimension: CGFloat = 1600

  enum CaptureError: LocalizedError {
    /// There is no preview running to take the photo with.
    case notRunning
    case unreadable

    var errorDescription: String? {
      switch self {
      case .notRunning: return "The camera is not running."
      case .unreadable: return "The photo could not be read."
      }
    }
  }

  /// Whether there is a camera to show. The iOS simulator has none.
  static var isAvailable: Bool {
#if os(iOS)
    QuestionCameraSession.device != nil
#elseif os(Android)
    AndroidQuestionCameraBridge.isAvailable
#else
    false
#endif
  }

  /// A still of what the preview shows, as an upright JPEG no larger than
  /// `maxDimension` on its longer side.
  static func capturePhoto() async throws -> Data {
#if os(iOS)
    return try await QuestionCameraSession.shared.capturePhoto()
#elseif os(Android)
    let base64 = try await Task.detached(priority: .userInitiated) {
      try AndroidQuestionCameraBridge.captureBase64()
    }.value
    guard !base64.isEmpty else { throw CaptureError.notRunning }
    guard let data = Data(base64Encoded: base64) else { throw CaptureError.unreadable }
    return data
#else
    throw CaptureError.notRunning
#endif
  }

#if !os(iOS)
  /// The photo in a file of its own, for `LocalPhotoThumbnail` to draw. The
  /// last one is cleared first, and each takes a new name, so the image
  /// loader never shows a cached earlier photo in its place.
  static func previewFile(for data: Data) -> URL? {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("QuestionPhotoPreview", isDirectory: true)
    try? FileManager.default.removeItem(at: directory)
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent("\(UUID().uuidString).jpg")
      try data.write(to: file)
      return file
    } catch {
      logger.error("[QuestionCamera] could not write the photo's preview: \(error.localizedDescription)")
      return nil
    }
  }
#endif

#if os(iOS)
  /// A photo as it is uploaded: an upright JPEG no larger than `maxDimension`
  /// on its longer side, whatever it arrived as — the camera's full-size
  /// capture, or a HEIC from the library.
  static func preparedForUpload(_ data: Data) throws -> Data {
    guard let image = downsampled(data, maxPixelSize: maxDimension),
          let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else {
      throw CaptureError.unreadable
    }
    return jpeg
  }

  /// The photo no larger than `maxPixelSize` on its longer side, upright.
  ///
  /// ImageIO decodes it at that size, never at the camera's full one, which
  /// takes a fraction of the time and memory of decoding and redrawing it.
  static func downsampled(_ data: Data, maxPixelSize: CGFloat) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
      return nil
    }
    return CGImageSourceCreateThumbnailAtIndex(source, 0, [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      // Bakes in the orientation the photo was taken in.
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ] as CFDictionary)
  }
#endif
}

#if os(iOS)
/// The capture session behind `QuestionCameraPreview`.
///
/// Everything that touches the session runs on `queue`, in order: starting and
/// stopping a session blocks, and a stop that overtook a start would leave the
/// camera running with nothing on screen.
final class QuestionCameraSession: @unchecked Sendable {
  static let shared = QuestionCameraSession()

  static var device: AVCaptureDevice? {
    AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
  }

  let session = AVCaptureSession()
  private let photoOutput = AVCapturePhotoOutput()
  private let queue = DispatchQueue(label: "com.yaronj.tim.question-camera")
  // Owned by `queue`.
  private var isConfigured = false
  private var previewCount = 0
  private var captures: [PhotoCapture] = []

  private init() {}

  /// A preview came on screen. Counted rather than flagged: SwiftUI can build
  /// the next preview before it takes the last one down.
  func previewAppeared() {
    queue.async { [self] in
      previewCount += 1
      configureIfNeeded()
      if !session.isRunning {
        session.startRunning()
      }
    }
  }

  func previewDisappeared() {
    queue.async { [self] in
      previewCount = max(0, previewCount - 1)
      if previewCount == 0, session.isRunning {
        session.stopRunning()
      }
    }
  }

  private func configureIfNeeded() {
    guard !isConfigured else { return }
    isConfigured = true
    session.beginConfiguration()
    session.sessionPreset = .photo
    if let device = Self.device,
       let input = try? AVCaptureDeviceInput(device: device),
       session.canAddInput(input) {
      session.addInput(input)
    }
    if session.canAddOutput(photoOutput) {
      session.addOutput(photoOutput)
      // Photos are uploaded at `maxDimension` on their longer side, so the
      // camera's smallest size that still covers it is all it need take.
      if let dimensions = Self.device?.activeFormat.supportedMaxPhotoDimensions
        .filter({ CGFloat(max($0.width, $0.height)) >= QuestionCamera.maxDimension })
        .min(by: { $0.width * $0.height < $1.width * $1.height }) {
        photoOutput.maxPhotoDimensions = dimensions
      }
      photoOutput.maxPhotoQualityPrioritization = .speed
    }
    session.commitConfiguration()
  }

  func capturePhoto() async throws -> Data {
    let photo: Data = try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        guard session.isRunning else {
          continuation.resume(throwing: QuestionCamera.CaptureError.notRunning)
          return
        }
        let capture = PhotoCapture { [weak self] capture, result in
          self?.queue.async {
            self?.captures.removeAll { $0 === capture }
          }
          continuation.resume(with: result)
        }
        // Kept until it reports: the output holds its delegate weakly.
        captures.append(capture)
        // Upright for a phone held in portrait, the only way the app runs.
        if let connection = photoOutput.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
          connection.videoRotationAngle = 90
        }
        let settings = AVCapturePhotoSettings()
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions
        // The student is waiting to see it, and a page of sums at
        // `maxDimension` reads as well without the extra processing.
        settings.photoQualityPrioritization = .speed
        photoOutput.capturePhoto(with: settings, delegate: capture)
      }
    }
    return try QuestionCamera.preparedForUpload(photo)
  }
}

private final class PhotoCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
  private let completion: @Sendable (PhotoCapture, Result<Data, Error>) -> Void

  init(completion: @escaping @Sendable (PhotoCapture, Result<Data, Error>) -> Void) {
    self.completion = completion
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
    if let error {
      completion(self, .failure(error))
    } else if let data = photo.fileDataRepresentation() {
      completion(self, .success(data))
    } else {
      completion(self, .failure(QuestionCamera.CaptureError.unreadable))
    }
  }
}
#endif

#if os(Android)
/// `AndroidQuestionCamera.kt`: the CameraX preview and the still it takes.
enum AndroidQuestionCameraBridge {
  private static let cameraClass = try! JClass(name: "teacher/minute/AndroidQuestionCamera")
  private static let createMethod = cameraClass.getStaticMethodID(
    name: "create",
    sig: "()Lskip/ui/ComposeView;"
  )!
  private static let isAvailableMethod = cameraClass.getStaticMethodID(
    name: "isAvailable",
    sig: "()Z"
  )!
  private static let captureBase64Method = cameraClass.getStaticMethodID(
    name: "captureBase64",
    sig: "()Ljava/lang/String;"
  )!

  /// One composer serves every render of the preview; the camera is bound
  /// while it is composed.
  static let preview: AndroidJavaObject? = jniContext {
    do {
      return try cameraClass.callStatic(method: createMethod, options: [.kotlincompat], args: [])
    } catch {
      logger.error("[QuestionCamera][Android] failed to create the preview: \(error)")
      return nil
    }
  }

  static var isAvailable: Bool {
    // The return type is spelled out: `callStatic` picks its JNI call from
    // it, and left to `try? … ?? false` it infers an object and calls a
    // method returning `boolean` as one, which aborts the process (see
    // `AndroidPermissionBridge.hasPermission`).
    let available: Bool? = try? jniContext {
      let value: Bool = try cameraClass.callStatic(method: isAvailableMethod, options: [.kotlincompat], args: [])
      return value
    }
    return available ?? false
  }

  /// Blocks until the photo is taken, so it is called off the main thread.
  static func captureBase64() throws -> String {
    try jniContext {
      try cameraClass.callStatic(method: captureBase64Method, options: [.kotlincompat], args: [])
    }
  }
}
#endif
