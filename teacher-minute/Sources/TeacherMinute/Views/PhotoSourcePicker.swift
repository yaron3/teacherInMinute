//
//  PhotoSourcePicker.swift
//  teacher-minute
//
//  A reusable image-source picker for the Apple platforms. SwiftUI's
//  PhotosPicker only reads the photo library, so this wraps a "Take Photo /
//  Choose from Library" chooser: the library goes through PhotosPicker and the
//  camera goes through UIImagePickerController. It mirrors the Android
//  camera-vs-gallery chooser so both platforms offer the same choice.
//

#if !os(Android)
import SwiftUI
@preconcurrency import PhotosUI
#if os(iOS)
import UIKit
#endif

func photoSourceDebug(_ message: String) {
  let formatted = "[PhotoSourcePicker] \(message)"
  print(formatted)
  logger.info("\(formatted)")
}

/// A tappable label that lets the user pick an image from the camera or the
/// photo library. The chosen image is delivered as JPEG/original `Data`.
struct PhotoSourceButton<Label: View>: View {
  let onImageData: (Data) -> Void
  @ViewBuilder var label: () -> Label

  @State private var showSourceDialog = false
  @State private var showLibraryPicker = false
  @State private var pickedItem: PhotosPickerItem?
#if os(iOS)
  @State private var showCamera = false
  @State private var pendingCameraRequest = false
#endif
  @State private var pendingLibraryRequest = false
  @State private var showCameraSettingsDialog = false

  /// Camera capture only exists on iOS; other Apple platforms fall through to
  /// the library picker alone.
  var photoSourceActions: [AppDialogAction] {
    var actions: [AppDialogAction] = []
#if os(iOS)
    actions.append(
      AppDialogAction(LocalizationSupport.localized("Take Photo")) {
        photoSourceDebug("Take Photo action selected")
        pendingCameraRequest = true
      }
    )
#endif
    actions.append(
      AppDialogAction(LocalizationSupport.localized("Choose from Library")) {
        photoSourceDebug("Choose from Library action selected")
        pendingLibraryRequest = true
      }
    )
    actions.append(AppDialogAction(LocalizationSupport.localized("Cancel"), kind: .cancel))
    return actions
  }

  var pendingCameraDescription: String {
#if os(iOS)
    return "\(pendingCameraRequest)"
#else
    return "unavailable"
#endif
  }

  var body: some View {
    Button {
      photoSourceDebug("Upload control tapped; presenting source dialog")
      showSourceDialog = true
    } label: {
      label()
    }
    .buttonStyle(.plain)
    // Attached to the button itself, so this needs the full-screen presentation
    // rather than an overlay bounded by the button's frame.
    .appDialog(
      LocalizationSupport.localized("Add a photo"),
      isPresented: $showSourceDialog,
      actions: photoSourceActions,
      coversScreen: true
    )
    .photosPicker(isPresented: $showLibraryPicker, selection: $pickedItem, matching: .images)
    .appDialog(
      LocalizationSupport.localized("Camera disabled"),
      isPresented: $showCameraSettingsDialog,
      message: LocalizationSupport.localized("Camera access is disabled. Open Settings and enable camera access to take a photo."),
      actions: [
        AppDialogAction(LocalizationSupport.localized("Cancel"), kind: .cancel),
        AppDialogAction(LocalizationSupport.localized("Open Settings")) {
          PermissionService.shared.openAppSettings()
        }
      ],
      coversScreen: true
    )
    .onChange(of: showSourceDialog) { _, isPresented in
      photoSourceDebug("source dialog presentation changed isPresented=\(isPresented) pendingCamera=\(pendingCameraDescription) pendingLibrary=\(pendingLibraryRequest)")
      guard !isPresented else { return }
      Task { @MainActor in
        photoSourceDebug("waiting for source dialog dismissal before presenting picker")
        try? await Task.sleep(nanoseconds: 350_000_000)
        presentPendingSource()
      }
    }
    .onChange(of: pickedItem) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          onImageData(data)
        }
        pickedItem = nil
      }
    }
#if os(iOS)
    .onChange(of: showCamera) { _, isPresented in
      photoSourceDebug("camera fullScreenCover changed isPresented=\(isPresented)")
    }
    .fullScreenCover(isPresented: $showCamera) {
      CameraImagePicker { data in
        onImageData(data)
      }
      .ignoresSafeArea()
    }
#endif
  }

  func presentPendingSource() {
    photoSourceDebug("presentPendingSource pendingCamera=\(pendingCameraDescription) pendingLibrary=\(pendingLibraryRequest)")

    if pendingLibraryRequest {
      pendingLibraryRequest = false
      photoSourceDebug("presenting PhotosPicker")
      showLibraryPicker = true
      return
    }

#if os(iOS)
    guard pendingCameraRequest else {
      photoSourceDebug("no pending source to present")
      return
    }
    pendingCameraRequest = false

    let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
    photoSourceDebug("camera source availability=\(cameraAvailable)")
    guard cameraAvailable else {
      photoSourceDebug("camera unavailable; falling back to PhotosPicker")
      showLibraryPicker = true
      return
    }

    Task { @MainActor in
      photoSourceDebug("requesting camera permission")
      let state = await PermissionService.shared.requestCapturePermission(for: .camera)
      photoSourceDebug("camera permission result=\(state.rawValue)")
      if state.isGranted {
        photoSourceDebug("setting showCamera=true")
        showCamera = true
      } else {
        photoSourceDebug("camera permission denied; presenting settings dialog")
        showCameraSettingsDialog = true
      }
    }
#endif
  }
}

#if os(iOS)
/// A camera-only image picker (SwiftUI's PhotosPicker cannot capture new
/// photos). Returns the captured image as JPEG `Data`.
struct CameraImagePicker: UIViewControllerRepresentable {
  let onImage: (Data) -> Void
  @Environment(\.dismiss) private var dismiss

  func makeUIViewController(context: Context) -> UIImagePickerController {
    photoSourceDebug("CameraImagePicker makeUIViewController")
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.modalPresentationStyle = .fullScreen
    picker.delegate = context.coordinator
    photoSourceDebug("CameraImagePicker configured sourceType=camera")
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
    photoSourceDebug("CameraImagePicker updateUIViewController")
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: CameraImagePicker
    init(_ parent: CameraImagePicker) { self.parent = parent }

    func imagePickerController(_ picker: UIImagePickerController,
                              didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      photoSourceDebug("CameraImagePicker didFinishPickingMediaWithInfo keys=\(info.keys.count)")
      if let image = info[.originalImage] as? UIImage,
         let data = image.jpegData(compressionQuality: 0.85) {
        photoSourceDebug("CameraImagePicker captured jpeg bytes=\(data.count)")
        parent.onImage(data)
      } else {
        photoSourceDebug("CameraImagePicker did not receive a JPEG-convertible original image")
      }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      photoSourceDebug("CameraImagePicker cancelled")
      parent.dismiss()
    }
  }
}
#endif
#endif
