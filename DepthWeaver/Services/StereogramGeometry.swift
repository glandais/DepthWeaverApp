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

    /// Output pixel size for a depth map: the aspect ratio is kept and the image
    /// upscaled by an integer factor until its min dimension reaches the target
    /// (960 by default — see `StereogramQuality`).
    static func outputSize(
        for depthMap: DepthMap,
        quality: StereogramQuality = .full
    ) -> (width: Int, height: Int) {
        let minDimTarget = quality.minDimension
        let rawWidth = depthMap.width > 0 ? depthMap.width : 1024
        let rawHeight = depthMap.height > 0 ? depthMap.height : 768
        let minDim = min(rawWidth, rawHeight)
        let scale = minDim < minDimTarget ? Int((Float(minDimTarget) / Float(minDim)).rounded(.up)) : 1
        return (rawWidth * scale, rawHeight * scale)
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
/// only affordable at a coarser output size; the moment the finger lifts the
/// canvas re-renders at `.full` and the two are indistinguishable again.
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
