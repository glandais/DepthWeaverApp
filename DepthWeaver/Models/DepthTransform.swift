import Foundation

/// A pan / zoom framing applied to a `DepthMap` *before* it reaches the
/// generator.
///
/// The canvas' live mode moves the depth *source* instead of the rendered
/// image: the stereogram is regenerated for the new framing rather than scaled
/// up, so the illusion keeps its full resolution while the map is dragged
/// around. `scale` is the zoom factor (1 frames the whole map) and the offsets
/// are fractions of the map, positive values pushing the content right / down.
struct DepthTransform: Equatable {
    var scale: Float = 1
    var offsetX: Float = 0
    var offsetY: Float = 0

    static let identity = DepthTransform()
    static let minScale: Float = 1
    static let maxScale: Float = 8

    var isIdentity: Bool { self == .identity }

    /// How far the window may travel before it would leave the map — zero at
    /// scale 1, where the whole map is already framed and there is nothing to
    /// pan towards.
    private var offsetLimit: Float {
        Swift.max(0, 0.5 - 0.5 / Swift.max(Self.minScale, scale))
    }

    /// Drags the content by a fraction of the *displayed* image size, so a
    /// finger travelling a given distance keeps the same amount of image under
    /// it at every zoom level.
    mutating func pan(dx: Float, dy: Float) {
        guard dx.isFinite, dy.isFinite else { return }
        let s = Swift.max(Self.minScale, scale)
        offsetX += dx / s
        offsetY += dy / s
        clampOffsets()
    }

    /// Zooms about the centre of the current window.
    mutating func zoom(by factor: Float) {
        guard factor.isFinite, factor > 0 else { return }
        scale = Swift.min(Swift.max(scale * factor, Self.minScale), Self.maxScale)
        clampOffsets()
    }

    mutating func clampOffsets() {
        let limit = offsetLimit
        offsetX = Swift.min(Swift.max(offsetX, -limit), limit)
        offsetY = Swift.min(Swift.max(offsetY, -limit), limit)
    }

    /// Precomputed so the sampling loops multiply rather than divide — and, more
    /// importantly, so the CPU and GPU paths perform the *same* fp32 operations
    /// and land on the same source pixel at a resample boundary.
    var inverseScale: Float { 1 / Swift.max(Self.minScale, scale) }

    /// Maps a normalized output coordinate to a normalized source coordinate.
    /// The GPU kernel runs this same line — keep them aligned.
    static func source(_ t: Float, inverseScale: Float, offset: Float) -> Float {
        Swift.min(1, Swift.max(0, 0.5 + (t - 0.5) * inverseScale - offset))
    }

    func sourceU(_ u: Float) -> Float {
        Self.source(u, inverseScale: inverseScale, offset: offsetX)
    }

    func sourceV(_ v: Float) -> Float {
        Self.source(v, inverseScale: inverseScale, offset: offsetY)
    }
}
