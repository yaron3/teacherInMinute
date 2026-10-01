import SwiftUI
#if os(iOS)
import AVFoundation
import UIKit
#elseif os(Android)
import SkipBridge
#endif

/// What the back camera sees, filling the space it is given. The camera runs
/// while this is on screen and stops when it leaves (see `QuestionCamera`).
struct QuestionCameraPreview: View {
  var body: some View {
#if os(iOS)
    CameraLayerView()
#elseif os(Android)
    if let preview = AndroidQuestionCameraBridge.preview,
       let view = JavaBackedView(preview.toJavaObject(options: [.kotlincompat])) {
      view
    } else {
      Color.black
    }
#else
    Color.black
#endif
  }
}

#if os(iOS)
private struct CameraLayerView: UIViewRepresentable {
  func makeUIView(context: Context) -> PreviewView {
    let view = PreviewView()
    view.backgroundColor = .black
    view.previewLayer.session = QuestionCameraSession.shared.session
    view.previewLayer.videoGravity = .resizeAspectFill
    QuestionCameraSession.shared.previewAppeared()
    return view
  }

  func updateUIView(_ uiView: PreviewView, context: Context) {}

  static func dismantleUIView(_ uiView: PreviewView, coordinator: ()) {
    QuestionCameraSession.shared.previewDisappeared()
  }

  final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
      layer as! AVCaptureVideoPreviewLayer
    }
  }
}
#endif
