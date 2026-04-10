import CoreImage
import CoreML
import os

private let logger = Logger(subsystem: "com.glandais.iStereogram", category: "DepthAnythingService")

final class DepthAnythingService {
    static let shared = DepthAnythingService()

    private let targetSize = CGSize(width: 518, height: 392)
    private let context = CIContext()
    private var model: DepthAnythingV2SmallF16?
    private let modelLock = NSLock()
    private let inputPixelBuffer: CVPixelBuffer

    private init() {
        var buffer: CVPixelBuffer!
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(targetSize.width),
            Int(targetSize.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess else {
            fatalError("Failed to create input pixel buffer")
        }
        inputPixelBuffer = buffer
    }

    func loadModel() throws {
        modelLock.lock()
        defer { modelLock.unlock() }
        guard model == nil else { return }
        logger.info("Loading Depth Anything V2 model...")
        let start = CFAbsoluteTimeGetCurrent()
        model = try DepthAnythingV2SmallF16()
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        logger.info("Model loaded in \(String(format: "%.2f", elapsed))s")
    }

    func estimateDepth(from image: CIImage) throws -> DepthMap {
        try loadModel()
        guard let model else {
            throw DepthEstimationError.modelNotLoaded
        }

        let originalWidth = image.extent.width
        let originalHeight = image.extent.height
        logger.info("Input image: \(Int(originalWidth))x\(Int(originalHeight))")

        // Resize to model input (stretches to 518x392)
        let resized = image.resized(to: targetSize)
        context.render(resized, to: inputPixelBuffer)

        let start = CFAbsoluteTimeGetCurrent()
        let result = try model.prediction(image: inputPixelBuffer)
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        logger.info("Depth estimation completed in \(String(format: "%.2f", elapsed))s")
        let depthBuffer = result.depth

        let depthWidth = CVPixelBufferGetWidth(depthBuffer)
        let depthHeight = CVPixelBufferGetHeight(depthBuffer)
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthBuffer)
        logger.info("Model output: \(depthWidth)x\(depthHeight), format=\(pixelFormat)")

        // Copy the depth buffer — CoreML reuses it on next prediction
        var copiedBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, depthWidth, depthHeight, pixelFormat, nil, &copiedBuffer)
        guard status == kCVReturnSuccess, let dst = copiedBuffer else {
            throw DepthEstimationError.bufferCopyFailed
        }

        CVPixelBufferLockBaseAddress(depthBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(dst, [])
        let srcData = CVPixelBufferGetBaseAddress(depthBuffer)!
        let dstData = CVPixelBufferGetBaseAddress(dst)!
        let srcBytesPerRow = CVPixelBufferGetBytesPerRow(depthBuffer)
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(dst)
        for row in 0..<depthHeight {
            memcpy(dstData + row * dstBytesPerRow, srcData + row * srcBytesPerRow, min(srcBytesPerRow, dstBytesPerRow))
        }
        CVPixelBufferUnlockBaseAddress(dst, [])
        CVPixelBufferUnlockBaseAddress(depthBuffer, .readOnly)

        // Compute output dimensions preserving original aspect ratio at model-output scale
        let aspectRatio = originalWidth / originalHeight
        let outWidth: Int
        let outHeight: Int
        if aspectRatio >= 1 {
            // Landscape or square: use model width, scale height
            outWidth = depthWidth
            outHeight = max(1, Int(Double(depthWidth) / aspectRatio))
        } else {
            // Portrait: use model height, scale width
            outHeight = depthHeight
            outWidth = max(1, Int(Double(depthHeight) * aspectRatio))
        }

        logger.info("Depth buffer copied, output=\(outWidth)x\(outHeight) (ratio preserved)")
        return DepthMap(
            pixelBuffer: dst,
            source: .depthAnything,
            originalWidth: outWidth,
            originalHeight: outHeight
        )
    }

    enum DepthEstimationError: LocalizedError {
        case modelNotLoaded
        case bufferCopyFailed

        var errorDescription: String? {
            switch self {
            case .modelNotLoaded: String(localized: "Failed to load depth estimation model")
            case .bufferCopyFailed: String(localized: "Failed to copy depth buffer")
            }
        }
    }
}
