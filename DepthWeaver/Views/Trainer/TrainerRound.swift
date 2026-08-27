#if os(iOS)
import CoreGraphics
import Foundation

/// The difficulty ladder the trainer walks up once the user says they can see
/// it.
///
/// What makes a stereogram easy is strong depth, a narrow eye separation (less
/// divergence to hold), and a pattern with obvious repeating landmarks. Each
/// round pulls one notch away from all three.
///
/// The patterns are all irregular on purpose: a regular grid (circles, mosaic,
/// hexagons) is resized to the band width, so its own cells repeat several
/// times *inside* every band and the eyes lock onto a cell instead of a band —
/// which reads as a much tighter, depthless image.
struct TrainerRound {
    let index: Int

    static let count = 4

    /// Clamped so an over-eager tap on the last round just repeats it.
    init(index: Int) {
        self.index = min(max(index, 0), TrainerRound.count - 1)
    }

    private var baseSettings: StereogramSettings {
        var settings = StereogramSettings()
        switch index {
        case 0:
            settings.depthStrength = 1.6
            settings.sepFactor = 0.44
            settings.oversampling = 4
            settings.patternSource = .asset(.stones)
        case 1:
            settings.depthStrength = 1.3
            settings.sepFactor = 0.50
            settings.oversampling = 4
            settings.patternSource = .asset(.dots)
        case 2:
            settings.depthStrength = 1.0
            settings.sepFactor = 0.57
            settings.oversampling = 4
            settings.patternSource = .asset(.noise)
        default:
            settings.depthStrength = 0.8
            settings.sepFactor = 0.64
            settings.oversampling = 5
            settings.patternSource = .procedural(.randomDot, ProceduralPatternType.randomDot.defaultConfig())
        }
        return settings
    }

    /// A bundled height map that reads as a sphere at trainer size — no new
    /// asset needed.
    var depthMap: DepthMap { DepthMapPreset.planet.toDepthMap() }

    /// The trainer canvas is a small circle while the main canvas fills the
    /// device, so the same DPI lands the pattern repeats far closer together
    /// here — and a narrow repeat is exactly what a beginner cannot diverge
    /// onto. Re-derive the DPI so one repeat covers as many points on screen as
    /// it does on the main canvas with its defaults.
    func settings(canvasSide: CGFloat, screen: CGSize) -> StereogramSettings {
        var settings = baseSettings
        let canvas = CGSize(width: canvasSide, height: canvasSide)
        let scale = StereogramGenerator.fillScale(
            imageSize: StereogramGenerator.outputSize(for: depthMap),
            in: canvas
        )
        guard scale > 0, screen.width > 0, screen.height > 0 else { return settings }
        // Matching outright would put fewer than two repeats inside the circle
        // on a large screen, and nothing fuses with less than a couple of them
        // to work with — so the match gives way to the repeat count.
        let band = min(TrainerRound.mainCanvasBand(screen: screen), canvasSide / 3)
        settings.dpi = StereogramGenerator.Geometry.dpi(
            forBandWidth: band / scale,
            depthStrength: settings.depthStrength
        )
        return settings
    }

    /// How wide one pattern repeat lands on the main canvas, in points: the
    /// default depth map and settings, scaled to fill the whole screen.
    private static func mainCanvasBand(screen: CGSize) -> CGFloat {
        let defaults = StereogramSettings()
        let geometry = StereogramGenerator.Geometry(
            dpi: defaults.dpi,
            depthStrength: defaults.depthStrength
        )
        let scale = StereogramGenerator.fillScale(imageSize: mainCanvasImageSize, in: screen)
        return CGFloat(geometry.maxsep) * scale
    }

    /// Decoding the default height map is not free, and its size never changes.
    private static let mainCanvasImageSize = StereogramGenerator.outputSize(
        for: DepthMapPreset.dog.toDepthMap()
    )

    var isLast: Bool { index >= TrainerRound.count - 1 }
    var next: TrainerRound { TrainerRound(index: index + 1) }
}
#endif
