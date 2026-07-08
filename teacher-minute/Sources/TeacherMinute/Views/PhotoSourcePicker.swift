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
#endif

  var body: some View {
    Button {
      showSourceDialog = true
    } label: {
      label()
    }
    .buttonStyle(.plain)
    .confirmationDialog(
      LocalizationSupport.localized("Add a photo"),
      isPresented: $showSourceDialog,
      titleVisibility: .visible
    ) {
#if os(iOS)
      Button(LocalizationSupport.localized("Take Photo")) {
        Task {
          let state = await PermissionService.shared.requestCapturePermission(for: .camera)
          if state.isGranted { showCamera = true }
        }
      }
#endif
      Button(LocalizationSupport.localized("Choose from Library")) {
        showLibraryPicker = true
      }
      Button(LocalizationSupport.localized("Cancel"), role: .cancel) {}
    }
    .photosPicker(isPresented: $showLibraryPicker, selection: $pickedItem, matching: .images)
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
    .sheet(isPresented: $showCamera) {
      CameraImagePicker { data in
        onImageData(data)
      }
      .ignoresSafeArea()
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
    let picker = UIImagePickerController()
    picker.sourceType = .camera
    picker.delegate = context.coordinator
    return picker
  }

  func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let parent: CameraImagePicker
    init(_ parent: CameraImagePicker) { self.parent = parent }

    func imagePickerController(_ picker: UIImagePickerController,
                              didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
      if let image = info[.originalImage] as? UIImage,
         let data = image.jpegData(compressionQuality: 0.85) {
        parent.onImage(data)
      }
      parent.dismiss()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
      parent.dismiss()
    }
  }
}
#endif
#endif
