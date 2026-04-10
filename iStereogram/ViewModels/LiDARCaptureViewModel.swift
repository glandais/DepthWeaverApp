import AVFoundation
import SwiftUI

@MainActor
final class LiDARCaptureViewModel: ObservableObject {
    @Published var cameraPermission: CameraPermission = .notDetermined

    enum CameraPermission {
        case notDetermined, authorized, denied
    }

    func checkPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraPermission = .authorized
        case .denied, .restricted:
            cameraPermission = .denied
        case .notDetermined:
            cameraPermission = .notDetermined
        @unknown default:
            cameraPermission = .notDetermined
        }
    }

    func requestPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraPermission = granted ? .authorized : .denied
    }
}
