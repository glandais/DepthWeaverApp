import CoreGraphics
import Foundation

extension StereogramGenerator {
    /// The pixel geometry the algorithm derives from the settings, factored out
    /// so callers that need to know how wide a pattern repeat comes out read it
    /// from the same formulas the generator runs on.
    struct Geometry {
        let dpi: Int
        let obsDist: Int
        let eyeSep: Int
        let maxdepth: Int
        /// Width in output pixels of one pattern repeat — the distance the eyes
        /// have to diverge by to fuse the image.
        let maxsep: Int

        init(dpi: Int, depthStrength: Float) {
            let xdpi = max(30, dpi)
            self.dpi = xdpi
            obsDist = xdpi * 12
            eyeSep = (xdpi * 5) / 2          // 2.5 inches
            maxdepth = max(1, Int((Float(obsDist) * max(0.1, depthStrength)).rounded()))
            maxsep = max(1, (eyeSep * maxdepth) / (maxdepth + obsDist))
        }

        /// Inverse of the `maxsep` derivation — `maxsep ≈ 2.5·dpi·strength / (strength + 1)`
        /// — so a caller can ask for a repeat of a given width instead of
        /// guessing at a DPI.
        static func dpi(forBandWidth bandWidth: CGFloat, depthStrength: Float) -> Int {
            let strength = max(0.1, depthStrength)
            let dpi = Float(bandWidth) * (strength + 1) / (2.5 * strength)
            return max(30, Int(dpi.rounded()))
        }
    }

    /// Raw pixel size of the depth map, with a fallback for an empty one.
    private static func rawSize(for depthMap: DepthMap) -> (width: Int, height: Int) {
        (
            depthMap.width > 0 ? depthMap.width : 1024,
            depthMap.height > 0 ? depthMap.height : 768
        )
    }

    /// The integer factor `outputSize` upscales a depth map by at a given
    /// quality — the resolution the render is spending, relative to the map.
    static func upscale(for depthMap: DepthMap, quality: StereogramQuality) -> Int {
        let minDimTarget = quality.minDimension
        let raw = rawSize(for: depthMap)
        let minDim = min(raw.width, raw.height)
        return minDim < minDimTarget ? Int((Float(minDimTarget) / Float(minDim)).rounded(.up)) : 1
    }

    /// Output pixel size for a depth map: the aspect ratio is kept and the image
    /// upscaled by an integer factor until its min dimension reaches the target
    /// (960 by default — see `StereogramQuality`).
    static func outputSize(
        for depthMap: DepthMap,
        quality: StereogramQuality = .full
    ) -> (width: Int, height: Int) {
        let raw = rawSize(for: depthMap)
        let scale = upscale(for: depthMap, quality: quality)
        return (raw.width * scale, raw.height * scale)
    }

    /// How much smaller a render at `quality` comes out than the full-quality
    /// one it stands in for.
    ///
    /// Every length the algorithm works in — the pattern repeat, the eye
    /// separation, the row shift — is a pixel count derived from the DPI, and
    /// none of them know how large the output is. Shrink the output without
    /// shrinking the DPI and the pattern band keeps its width while the image
    /// around it halves, so the preview reads as a zoomed-in stereogram rather
    /// than a coarser one. Scaling the DPI by this factor makes a `.preview`
    /// frame the *same* image at a lower resolution.
    static func renderScale(for depthMap: DepthMap, quality: StereogramQuality) -> Float {
        let full = upscale(for: depthMap, quality: .full)
        guard full > 0 else { return 1 }
        return Float(upscale(for: depthMap, quality: quality)) / Float(full)
    }

    /// The factor `.scaledToFill` applies to an image of `imageSize` shown in a
    /// `target`-sized frame.
    static func fillScale(imageSize: (width: Int, height: Int), in target: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 0 }
        return max(target.width / CGFloat(imageSize.width), target.height / CGFloat(imageSize.height))
    }
}

/// How much resolution a render is allowed to spend.
///
/// Live mode regenerates the whole stereogram on every gesture frame, which is
/// only affordable at a coarser output size; the geometry is scaled with it
/// (see `renderScale`) so a preview frame differs from the `.full` render the
/// finger lifting brings back only in sharpness, never in framing.
enum StereogramQuality {
    case preview
    case full

    var minDimension: Int {
        switch self {
        case .preview: return 480
        case .full: return 960
        }
    }
}
