import CoreImage
import ImageIO
import SwiftUI

#if os(iOS)
import PhotosUI
#endif

@MainActor
final class PhotoDepthViewModel: ObservableObject {
    @Published var depthMap: DepthMap?
    @Published var isProcessing = false
    @Published var showError = false
    @Published var errorMessage = ""
    /// How long the last successful estimate took, surfaced as the
    /// "ESTIMATED IN 1.2s" badge on the depth-source screen.
    @Published private(set) var lastEstimateDuration: TimeInterval?

    func processImage(data: Data) async {
        isProcessing = true
        defer { isProcessing = false }
        await runImageProcessing(data: data)
    }

    func processImage(at url: URL) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let data = try Data(contentsOf: url)
            await runImageProcessing(data: data)
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    #if os(iOS)
    func processPhoto(item: PhotosPickerItem) async {
        isProcessing = true
        defer { isProcessing = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                showError(message: String(localized: "error.photo_load_failed"))
                return
            }
            await runImageProcessing(data: data)
        } catch {
            showError(message: error.localizedDescription)
        }
    }
    #endif

    private func runImageProcessing(data: Data) async {
        do {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                showError(message: String(localized: "error.photo_load_failed"))
                return
            }

            let exif = Self.exifOrientation(from: source)
            let ciImage = CIImage(cgImage: cgImage)
                .oriented(forExifOrientation: Int32(exif))
            let started = Date()
            depthMap = try DepthAnythingService.shared.estimateDepth(from: ciImage)
            lastEstimateDuration = Date().timeIntervalSince(started)
        } catch {
            showError(message: error.localizedDescription)
        }
    }

    private static func exifOrientation(from source: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let raw = props[kCGImagePropertyOrientation] as? Int
        else {
            return 1
        }
        return raw
    }

    private func showError(message: String) {
        errorMessage = message
        showError = true
    }
}
