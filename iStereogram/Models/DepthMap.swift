import CoreImage
import CoreVideo
import os
import UIKit

private let logger = Logger(subsystem: "com.glandais.iStereogram", category: "DepthMap")

struct DepthMap: Identifiable {
    let id = UUID()

    enum Source {
        case lidar
        case depthAnything
    }

    let pixelBuffer: CVPixelBuffer
    let source: Source
    /// Original image dimensions (after orientation), used to restore aspect ratio.
    /// If nil, uses the pixel buffer dimensions directly.
    let originalWidth: Int?
    let originalHeight: Int?

    var width: Int { originalWidth ?? CVPixelBufferGetWidth(pixelBuffer) }
    var height: Int { originalHeight ?? CVPixelBufferGetHeight(pixelBuffer) }

    /// Returns a normalized grayscale UIImage for preview display.
    func previewImage() -> UIImage? {
        let w = width
        let h = height
        logger.info("previewImage() called, \(w)x\(h)")
        let normalized = normalizedDepthValues(width: w, height: h)

        var pixels = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            pixels[i] = UInt8(normalized[i] * 255)
        }

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: w, height: h,
                  bitsPerComponent: 8, bitsPerPixel: 8,
                  bytesPerRow: w,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: 0),
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              )
        else {
            logger.error("Failed to create CGImage")
            return nil
        }
        logger.info("previewImage() succeeded")
        return UIImage(cgImage: cgImage)
    }

    /// Extracts normalized [0..1] depth values resized to the given dimensions.
    func normalizedDepthValues(width targetWidth: Int, height targetHeight: Int) -> [Float] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let srcWidth = CVPixelBufferGetWidth(pixelBuffer)
        let srcHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            logger.error("baseAddress is nil")
            return [Float](repeating: 0, count: targetWidth * targetHeight)
        }

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let bytesPerPixel = bytesPerRow / srcWidth
        logger.info("normalizedDepthValues: \(srcWidth)x\(srcHeight), format=\(pixelFormat), bytesPerRow=\(bytesPerRow), bytesPerPixel=\(bytesPerPixel)")

        let srcFloats: [Float]

        // Detect float32 formats by bytes-per-pixel (4 bytes = 32-bit float)
        // This covers kCVPixelFormatType_DepthFloat32, kCVPixelFormatType_OneComponent32Float, etc.
        if bytesPerPixel >= 4 {
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            let rowFloats = bytesPerRow / MemoryLayout<Float>.size
            srcFloats = (0..<srcHeight).flatMap { y in
                (0..<srcWidth).map { x in floatBuffer[y * rowFloats + x] }
            }
        } else if bytesPerPixel == 2 {
            // Float16 depth
            let float16Buffer = baseAddress.assumingMemoryBound(to: Float16.self)
            let rowHalfs = bytesPerRow / MemoryLayout<Float16>.size
            srcFloats = (0..<srcHeight).flatMap { y in
                (0..<srcWidth).map { x in Float(float16Buffer[y * rowHalfs + x]) }
            }
        } else {
            // Fallback: interpret as 8-bit grayscale
            let uint8Buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            srcFloats = (0..<srcHeight).flatMap { y in
                (0..<srcWidth).map { x in Float(uint8Buffer[y * bytesPerRow + x]) / 255.0 }
            }
        }

        // Find min/max for normalization
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        for v in srcFloats {
            if v.isFinite {
                minVal = min(minVal, v)
                maxVal = max(maxVal, v)
            }
        }
        let range = maxVal - minVal
        let safeRange = range > 0 ? range : 1.0
        logger.info("Depth range: min=\(minVal), max=\(maxVal)")

        // Resize with bilinear interpolation and normalize
        var result = [Float](repeating: 0, count: targetWidth * targetHeight)
        for y in 0..<targetHeight {
            let srcY = Float(y) * Float(srcHeight - 1) / Float(max(1, targetHeight - 1))
            let y0 = Int(srcY)
            let y1 = min(y0 + 1, srcHeight - 1)
            let fy = srcY - Float(y0)

            for x in 0..<targetWidth {
                let srcX = Float(x) * Float(srcWidth - 1) / Float(max(1, targetWidth - 1))
                let x0 = Int(srcX)
                let x1 = min(x0 + 1, srcWidth - 1)
                let fx = srcX - Float(x0)

                let v00 = srcFloats[y0 * srcWidth + x0]
                let v10 = srcFloats[y0 * srcWidth + x1]
                let v01 = srcFloats[y1 * srcWidth + x0]
                let v11 = srcFloats[y1 * srcWidth + x1]

                let interpolated = v00 * (1 - fx) * (1 - fy)
                    + v10 * fx * (1 - fy)
                    + v01 * (1 - fx) * fy
                    + v11 * fx * fy

                var normalized = (interpolated - minVal) / safeRange
                // LiDAR depth is in meters (closer = smaller value), invert so closer = 1.0
                if source == .lidar {
                    normalized = 1.0 - normalized
                }
                result[y * targetWidth + x] = max(0, min(1, normalized))
            }
        }
        return result
    }

}
