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

    let source: Source
    let sourceWidth: Int
    let sourceHeight: Int
    /// Original image dimensions (after orientation), used to restore aspect ratio.
    /// If nil, uses the source dimensions directly.
    let originalWidth: Int?
    let originalHeight: Int?
    /// Raw depth values at source resolution, as extracted from the pixel buffer.
    /// LiDAR: meters (closer = smaller). AI: arbitrary range normalized to [0..1].
    let originalDepth: [Float]

    var adjustment: DepthAdjustment

    var width: Int { originalWidth ?? sourceWidth }
    var height: Int { originalHeight ?? sourceHeight }

    /// Creates a DepthMap from a CVPixelBuffer, extracting and storing the raw depth values.
    init(pixelBuffer: CVPixelBuffer, source: Source, originalWidth: Int?, originalHeight: Int?) {
        self.source = source
        self.sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        self.sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.originalDepth = Self.extractRawDepth(from: pixelBuffer, width: self.sourceWidth, height: self.sourceHeight)
        self.adjustment = Self.initialAdjustment(source: source, rawDepth: self.originalDepth)
    }

    /// Computes initial adjustment values based on the source type and raw depth range.
    static func initialAdjustment(source: Source, rawDepth: [Float]) -> DepthAdjustment {
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        for v in rawDepth where v.isFinite {
            minVal = Swift.min(minVal, v)
            maxVal = Swift.max(maxVal, v)
        }
        if minVal >= maxVal {
            minVal = 0
            maxVal = 1
        }
        logger.info("Raw depth range: \(minVal)...\(maxVal)")

        switch source {
        case .lidar:
            // LiDAR values are in meters (closer = smaller).
            // Invert: map [min..max] → [1..0] so closer objects are brighter.
            return DepthAdjustment(min: minVal, max: maxVal, start: 1, end: 0)
        case .depthAnything:
            // AI depth is already normalized, identity mapping.
            return DepthAdjustment(min: minVal, max: maxVal, start: 0, end: 1)
        }
    }

    /// The absolute min/max of raw depth values, for slider bounds.
    var rawDepthRange: ClosedRange<Float> {
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        for v in originalDepth where v.isFinite {
            minVal = Swift.min(minVal, v)
            maxVal = Swift.max(maxVal, v)
        }
        if minVal >= maxVal { return 0...1 }
        return minVal...maxVal
    }

    /// Returns a normalized grayscale UIImage for preview display.
    func previewImage() -> UIImage? {
        let w = width
        let h = height
        let adjusted = adjustedDepthValues(width: w, height: h)

        var pixels = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            pixels[i] = UInt8(adjusted[i] * 255)
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
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Returns adjusted [0..1] depth values resized to the given dimensions.
    /// Applies the depth adjustment: clamp to [min, max], remap to [start, end].
    func adjustedDepthValues(width targetWidth: Int, height targetHeight: Int) -> [Float] {
        let adjMin = adjustment.min
        let adjMax = adjustment.max
        let adjStart = adjustment.start
        let adjEnd = adjustment.end
        let adjRange = adjMax - adjMin
        let safeRange = adjRange > 0 ? adjRange : 1.0

        var result = [Float](repeating: 0, count: targetWidth * targetHeight)
        for y in 0..<targetHeight {
            let srcY = Float(y) * Float(sourceHeight - 1) / Float(Swift.max(1, targetHeight - 1))
            let y0 = Int(srcY)
            let y1 = Swift.min(y0 + 1, sourceHeight - 1)
            let fy = srcY - Float(y0)

            for x in 0..<targetWidth {
                let srcX = Float(x) * Float(sourceWidth - 1) / Float(Swift.max(1, targetWidth - 1))
                let x0 = Int(srcX)
                let x1 = Swift.min(x0 + 1, sourceWidth - 1)
                let fx = srcX - Float(x0)

                let v00 = originalDepth[y0 * sourceWidth + x0]
                let v10 = originalDepth[y0 * sourceWidth + x1]
                let v01 = originalDepth[y1 * sourceWidth + x0]
                let v11 = originalDepth[y1 * sourceWidth + x1]

                let interpolated = v00 * (1 - fx) * (1 - fy)
                    + v10 * fx * (1 - fy)
                    + v01 * (1 - fx) * fy
                    + v11 * fx * fy

                // Clamp to [min, max], normalize to [0..1], remap to [start, end]
                let clamped = Swift.min(1, Swift.max(0, (interpolated - adjMin) / safeRange))
                let remapped = adjStart + clamped * (adjEnd - adjStart)
                result[y * targetWidth + x] = Swift.max(0, Swift.min(1, remapped))
            }
        }
        return result
    }

    // MARK: - Raw Depth Extraction

    private static func extractRawDepth(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> [Float] {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            return [Float](repeating: 0, count: width * height)
        }

        let bytesPerPixel = bytesPerRow / width
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        logger.info("extractRawDepth: \(width)x\(height), format=\(pixelFormat), bpp=\(bytesPerPixel)")

        if bytesPerPixel >= 4 {
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            let rowFloats = bytesPerRow / MemoryLayout<Float>.size
            return (0..<height).flatMap { y in
                (0..<width).map { x in floatBuffer[y * rowFloats + x] }
            }
        } else if bytesPerPixel == 2 {
            let float16Buffer = baseAddress.assumingMemoryBound(to: Float16.self)
            let rowHalfs = bytesPerRow / MemoryLayout<Float16>.size
            return (0..<height).flatMap { y in
                (0..<width).map { x in Float(float16Buffer[y * rowHalfs + x]) }
            }
        } else {
            let uint8Buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
            return (0..<height).flatMap { y in
                (0..<width).map { x in Float(uint8Buffer[y * bytesPerRow + x]) / 255.0 }
            }
        }
    }
}
