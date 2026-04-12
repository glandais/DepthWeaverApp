import CoreImage
import PhotosUI
import SwiftUI

@MainActor
final class PhotoDepthViewModel: ObservableObject {
    @Published var depthMap: DepthMap?
    @Published var isProcessing = false
    @Published var showError = false
    @Published var errorMessage = ""

    func processPhoto(item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let uiImage = UIImage(data: data),
                  let cgImage = uiImage.cgImage
            else {
                showError(message: String(localized: "error.photo_load_failed"))
                return
            }

            // Apply EXIF orientation so the image is fed to the model correctly
            let ciImage = CIImage(cgImage: cgImage)
                .oriented(forExifOrientation: Int32(uiImage.imageOrientation.exifOrientation))
            let result = try DepthAnythingService.shared.estimateDepth(from: ciImage)
            depthMap = result
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
