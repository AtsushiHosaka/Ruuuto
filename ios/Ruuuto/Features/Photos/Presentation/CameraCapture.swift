import AVFoundation
import SwiftUI
import UIKit

/// アプリ内カメラが使えるか（RCNO-16）
enum CameraAccess: Equatable {
    case authorized
    case notDetermined
    /// 利用者が拒否した、または機能制限で使えない。設定アプリで変えられる
    case denied
    /// この端末にカメラがない（シミュレータなど）
    case unavailable

    static func current() -> CameraAccess {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return .unavailable }
        return switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// まだ聞いていなければ許可を求め、結果を返す。理由の文言は NSCameraUsageDescription。
    static func requestIfNeeded() async -> CameraAccess {
        let access = current()
        guard access == .notDetermined else { return access }
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return current()
    }
}

/// iOS 標準のカメラ画面。撮影後の「再撮影」と「写真を使用」、取消は標準の操作をそのまま使う。
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
