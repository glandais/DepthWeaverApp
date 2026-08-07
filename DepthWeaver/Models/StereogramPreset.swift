import Foundation

/// The three one-tap looks offered above the Tune sliders.
///
/// Presets deliberately leave `dpi` alone: DPI lives behind Advanced, so
/// keeping it out means changing it never knocks the user out of a preset.
/// "Custom" is not a case here — it is what the UI shows when
/// ``matching(_:)`` finds no match.
enum StereogramPreset: String, CaseIterable, Identifiable {
    case soft
    case standard
    case punchy

    var id: String { rawValue }

    var depthStrength: Float {
        switch self {
        case .soft: 0.70
        case .standard: 1.00
        case .punchy: 1.50
        }
    }

    var sepFactor: Float {
        switch self {
        case .soft: 0.46
        case .standard: 0.55
        case .punchy: 0.64
        }
    }

    var oversampling: Int {
        switch self {
        case .soft: 4
        case .standard: 4
        case .punchy: 5
        }
    }

    func apply(to settings: inout StereogramSettings) {
        settings.depthStrength = depthStrength
        settings.sepFactor = sepFactor
        settings.oversampling = oversampling
    }

    /// The preset the given settings correspond to, or `nil` for "Custom".
    static func matching(_ settings: StereogramSettings) -> StereogramPreset? {
        allCases.first { preset in
            abs(settings.depthStrength - preset.depthStrength) < 0.001
                && abs(settings.sepFactor - preset.sepFactor) < 0.001
                && settings.oversampling == preset.oversampling
        }
    }
}
