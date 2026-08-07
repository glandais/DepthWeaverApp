#if os(iOS)
import Foundation

/// The difficulty ladder the trainer walks up once the user says they can see
/// it.
///
/// What makes a stereogram easy is strong depth, a narrow eye separation (less
/// divergence to hold), and a pattern with obvious repeating landmarks. Each
/// round pulls one notch away from all three.
struct TrainerRound {
    let index: Int

    static let count = 4

    /// Clamped so an over-eager tap on the last round just repeats it.
    init(index: Int) {
        self.index = min(max(index, 0), TrainerRound.count - 1)
    }

    var settings: StereogramSettings {
        var settings = StereogramSettings()
        switch index {
        case 0:
            settings.depthStrength = 1.6
            settings.sepFactor = 0.44
            settings.oversampling = 4
            settings.patternSource = .asset(.circles)
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

    var isLast: Bool { index >= TrainerRound.count - 1 }
    var next: TrainerRound { TrainerRound(index: index + 1) }
}
#endif
