import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics
import os

private let logger = Logger(subsystem: "com.glandais.DepthWeaver", category: "DepthMapDenoiser")

/// Core Image-based denoising for 8-bit imported depth maps.
///
/// Pipeline (in half-float working space): normalize → median → background mask → bilateral → blend.
/// The half-float working format is what lifts values out of the 8-bit quantization grid;
/// the bilateral interpolates between source paliers instead of reinforcing them.
final class DepthMapDenoiser: @unchecked Sendable {
    static let shared = DepthMapDenoiser()

    private let bilateralRadius: Float = 6
    private let medianIterations: Int = 1
    private let backgroundIsDark: Bool = true
    private let backgroundValue: Float = 0
    private let finalSmoothRadius: Float = 1.0

    private let context: CIContext = {
        CIContext(options: [
            .workingFormat: NSNumber(value: CIFormat.RGBAh.rawValue),
            .useSoftwareRenderer: false
        ])
    }()

    func denoise(pixels: [Float], width: Int, height: Int, parameters: DepthDenoising) -> [Float] {
        let count = width * height
        guard width > 0, height > 0, pixels.count == count else { return pixels }

        let bytesPerRow = width * MemoryLayout<Float>.size
        let size = CGSize(width: width, height: height)
        let extent = CGRect(origin: .zero, size: size)

        let inputData = pixels.withUnsafeBytes { Data($0) }
        // colorSpace nil → linear, no gamma correction; matches the working color space.
        let raw = CIImage(
            bitmapData: inputData,
            bytesPerRow: bytesPerRow,
            size: size,
            format: .Rf,
            colorSpace: nil
        )

        // Progressive debugging: median + normalize to RGBA + bilateral.
        var depth = raw
        for _ in 0..<medianIterations {
            depth = depth.applyingFilter("CIMedianFilter").cropped(to: extent)
        }

        // Promote .Rf to explicit (R, R, R, 1) RGBA so bilateral has well-defined inputs.
        depth = depth.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 1, y: 0, z: 0, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ]).cropped(to: extent)

        depth = depth.applyingFilter("CINoiseReduction", parameters: [
            "inputNoiseLevel": parameters.bilateralIntensity * 0.1,
            "inputSharpness": 0.4
        ]).cropped(to: extent)

        if finalSmoothRadius > 0 {
            depth = depth.applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: finalSmoothRadius
            ]).cropped(to: extent)
        }

        let mask = backgroundMask(from: depth, extent: extent, parameters: parameters)
        let composed = compose(smoothed: depth, mask: mask, extent: extent)

        var output = [Float](repeating: 0, count: count)
        output.withUnsafeMutableBytes { buf in
            guard let base = buf.baseAddress else { return }
            context.render(
                composed,
                toBitmap: base,
                rowBytes: bytesPerRow,
                bounds: extent,
                format: .Rf,
                colorSpace: nil
            )
        }

        for i in 0..<count {
            output[i] = Swift.max(0, Swift.min(1, output[i]))
        }

        logger.debug("Denoised \(width)x\(height) (intensity=\(parameters.bilateralIntensity), morph=\(parameters.morphologyRadius), thresh=\(parameters.backgroundThreshold))")
        return output
    }

    /// Returns a mask CIImage where (R, G, B, A) all equal m ∈ [0, 1].
    /// m = 1 where the input depth belongs to the "background" (uniform region to flatten).
    private func backgroundMask(from depth: CIImage, extent: CGRect, parameters: DepthDenoising) -> CIImage {
        // Build a sharp step: f(d) = clamp(0, 1, scale * d + biasOffset).
        // backgroundIsDark: m = 1 for d ≤ t → scale negative, bias = scale*t + 1 swapped to positive.
        // backgroundIsDark==false: m = 1 for d ≥ t → scale positive, bias chosen accordingly.
        let t = CGFloat(parameters.backgroundThreshold)
        let stepScale: CGFloat = 1000
        let scale: CGFloat = backgroundIsDark ? -stepScale : stepScale
        let biasOffset: CGFloat = backgroundIsDark ? (stepScale * t + 1) : (-stepScale * t + 1)

        // R_out = scale * R_in + biasOffset (others identical) — alpha mirrors RGB.
        var mask = depth
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                "inputAVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: biasOffset, y: biasOffset, z: biasOffset, w: biasOffset)
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: extent)

        let r = parameters.morphologyRadius
        if r > 0 {
            // Closing (max → min) closes holes; opening (min → max) smooths edges and removes specks.
            mask = mask
                .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: r])
                .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: r])
                .applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: r])
                .applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: r])
                .cropped(to: extent)
        }

        // Light feather to anti-alias the mask edge — sharp transitions show as stripes in SIRDS.
        return mask
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 1.0])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: extent)
    }

    /// Computes `smoothed * (1 - mask) + bgValue * mask` channel-by-channel via explicit
    /// multiply + add compositing. Avoids ambiguity over which mask channel
    /// `CIBlendWithMask` reads (luminance vs. alpha across iOS versions).
    private func compose(smoothed: CIImage, mask: CIImage, extent: CGRect) -> CIImage {
        let bg = CGFloat(backgroundValue)
        let bgImage = CIImage(color: CIColor(red: bg, green: bg, blue: bg, alpha: 1)).cropped(to: extent)

        // (1 - mask): invert RGB and alpha consistently via matrix (CIColorInvert leaves alpha alone).
        let inverseMask = mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: -1, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: -1, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: -1, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: -1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 1)
        ]).cropped(to: extent)

        // smoothed * (1 - mask)
        let smoothedPart = smoothed.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: inverseMask
        ]).cropped(to: extent)

        // bgImage * mask
        let bgPart = bgImage.applyingFilter("CIMultiplyCompositing", parameters: [
            kCIInputBackgroundImageKey: mask
        ]).cropped(to: extent)

        // Sum the two parts.
        return smoothedPart.applyingFilter("CIAdditionCompositing", parameters: [
            kCIInputBackgroundImageKey: bgPart
        ]).cropped(to: extent)
    }
}
