import CoreImage
import CoreVideo
import os
import UIKit

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "DepthMap")

struct DepthMap: Identifiable {
    let id = UUID()

    enum Source {
        case lidar
        case depthAnything
        case imported
        case model3D
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
    var denoising: DepthDenoising
    /// Cached denoised version of `originalDepth` at sourceWidth × sourceHeight.
    /// Populated only when `denoising.enabled && source == .imported`.
    private(set) var denoisedDepth: [Float]?

    var width: Int { originalWidth ?? sourceWidth }
    var height: Int { originalHeight ?? sourceHeight }

    /// The depth array consumed by `adjustedDepthValues` and `rawDepthRange`.
    var workingDepth: [Float] {
        denoising.enabled ? (denoisedDepth ?? originalDepth) : originalDepth
    }

    /// Recomputes `denoisedDepth` from `originalDepth` using current `denoising` parameters.
    /// Heavy CI work — call from a background queue.
    mutating func applyDenoising() {
        guard denoising.enabled, source == .imported else {
            denoisedDepth = nil
            return
        }
        denoisedDepth = DepthMapDenoiser.shared.denoise(
            pixels: originalDepth,
            width: sourceWidth,
            height: sourceHeight,
            parameters: denoising
        )
    }

    /// Updates the denoising state and precomputed buffer atomically.
    /// Use this when the buffer was already computed on a background queue.
    mutating func setDenoising(_ params: DepthDenoising, denoisedDepth: [Float]?) {
        self.denoising = params
        self.denoisedDepth = denoisedDepth
    }

    /// Creates a DepthMap from a CVPixelBuffer, extracting and storing the raw depth values.
    init(pixelBuffer: CVPixelBuffer, source: Source, originalWidth: Int?, originalHeight: Int?) {
        self.source = source
        self.sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        self.sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        self.originalWidth = originalWidth
        self.originalHeight = originalHeight
        self.originalDepth = Self.extractRawDepth(from: pixelBuffer, width: self.sourceWidth, height: self.sourceHeight)
        self.adjustment = Self.initialAdjustment(rawDepth: self.originalDepth)
        self.denoising = DepthDenoising()
        self.denoisedDepth = nil
    }

    /// Computes initial adjustment values based on the source type and raw depth range.
    static func initialAdjustment(rawDepth: [Float]) -> DepthAdjustment {
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

        return DepthAdjustment(min: minVal, max: maxVal, start: 0, end: 1)
    }

    /// The absolute min/max of raw depth values, for slider bounds.
    var rawDepthRange: ClosedRange<Float> {
        var minVal: Float = .greatestFiniteMagnitude
        var maxVal: Float = -.greatestFiniteMagnitude
        for v in workingDepth where v.isFinite {
            minVal = Swift.min(minVal, v)
            maxVal = Swift.max(maxVal, v)
        }
        if minVal >= maxVal { return 0...1 }
        return minVal...maxVal
    }

    /// Returns a hue-mapped UIImage for preview display.
    /// - Parameter highlightClamped: When true, clamped pixels (0 or 1) are drawn in red.
    func previewImage(highlightClamped: Bool = false) -> UIImage? {
        let w = width
        let h = height
        let adjusted = adjustedDepthValues(width: w, height: h)

        // RGBA pixels: map depth to hue wheel, clamped pixels optionally highlighted
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let v = adjusted[i]
            let oi = i * 4

            let (r, g, b) = Self.hueColor(forNormalized: v, highlightClamped: highlightClamped)
            pixels[oi]     = UInt8(r * 255)
            pixels[oi + 1] = UInt8(g * 255)
            pixels[oi + 2] = UInt8(b * 255)
            pixels[oi + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cgImage = CGImage(
                  width: w, height: h,
                  bitsPerComponent: 8, bitsPerPixel: 32,
                  bytesPerRow: w * 4,
                  space: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
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

    /// Shared hue-ramp palette for depth visualization.
    /// Returns (r, g, b) in [0..1]. Clamped values (v<=0 or v>=1) become bright red when `highlightClamped` is true.
    static func hueColor(forNormalized v: Float, highlightClamped: Bool = false) -> (CGFloat, CGFloat, CGFloat) {
        if highlightClamped && (v <= 0 || v >= 1) {
            return (1.0, 40.0/255.0, 40.0/255.0)
        }
        let hue = (0.83 - CGFloat(v) * 0.66).truncatingRemainder(dividingBy: 1.0)
        let color = UIColor(hue: hue, saturation: 0.85, brightness: 0.95, alpha: 1)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        return (r, g, b)
    }

    /// Returns adjusted [0..1] depth values resized to the given dimensions.
    /// Applies the depth adjustment: clamp to [min, max], remap to [start, end].
    func adjustedDepthValues(width targetWidth: Int, height targetHeight: Int) -> [Float] {
        let adjMin = adjustment.min
        let adjMax = adjustment.max
        let adjStart = 1.0 - adjustment.start
        let adjEnd = 1.0 - adjustment.end
        let adjRange = adjMax - adjMin
        let safeRange = adjRange > 0 ? adjRange : 1.0
        let depthSource = workingDepth

        var result = [Float](repeating: 0, count: targetWidth * targetHeight)
        for y in 0..<targetHeight {
            let srcY = Float(y) * Float(sourceHeight - 1) / Float(Swift.max(1, targetHeight - 1))
            let y0 = Int(srcY)

            for x in 0..<targetWidth {
                let srcX = Float(x) * Float(sourceWidth - 1) / Float(Swift.max(1, targetWidth - 1))
                let x0 = Int(srcX)

                let v00 = depthSource[y0 * sourceWidth + x0]

                // Clamp to [min, max], normalize to [0..1], remap to [start, end]
                let clamped = Swift.min(1, Swift.max(0, (v00 - adjMin) / safeRange))
                let remapped = adjStart + clamped * (adjEnd - adjStart)
                result[y * targetWidth + x] = Swift.max(0, Swift.min(1, remapped))
            }
        }
        return result
    }

    /// Creates a DepthMap from a UIImage, interpreting brightness as depth.
    init(image: UIImage) {
        let cgImage: CGImage
        if let cg = image.cgImage {
            cgImage = cg
        } else if let ciImage = image.ciImage {
            let context = CIContext()
            cgImage = context.createCGImage(ciImage, from: ciImage.extent)!
        } else {
            fatalError("UIImage has no cgImage or ciImage")
        }

        let maxSide = 1024
        let origW = cgImage.width
        let origH = cgImage.height
        let scale = Swift.min(1.0, Double(maxSide) / Double(Swift.max(origW, origH)))
        let w = Int(Double(origW) * scale)
        let h = Int(Double(origH) * scale)

        self.source = .imported
        self.sourceWidth = w
        self.sourceHeight = h
        self.originalWidth = nil
        self.originalHeight = nil

        // Render to grayscale 8-bit buffer
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: w * h)
        guard let ctx = CGContext(
            data: &pixels,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            self.originalDepth = [Float](repeating: 0, count: w * h)
            self.adjustment = Self.initialAdjustment(rawDepth: self.originalDepth)
            self.denoising = DepthDenoising()
            self.denoisedDepth = nil
            return
        }
        ctx.interpolationQuality = .none
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        let raw = pixels.map { Float($0) / 255.0 }
        self.originalDepth = raw
        self.denoising = DepthDenoising.defaultsForImported
        self.denoisedDepth = DepthMapDenoiser.shared.denoise(
            pixels: raw,
            width: w,
            height: h,
            parameters: self.denoising
        )
        self.adjustment = Self.initialAdjustment(rawDepth: self.denoisedDepth ?? raw)
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
