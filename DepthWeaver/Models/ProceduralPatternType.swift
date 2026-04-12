import SwiftUI

// MARK: - Procedural Pattern Type

enum ProceduralPatternType: String, CaseIterable, Identifiable, Equatable {
    case randomDot
    case stars
    case perlinNoise
    case worleyNoise
    case voronoi
    case reactionDiffusion

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .randomDot: String(localized: "pattern.random_dot", comment: "Pattern name")
        case .stars: String(localized: "pattern.stars", comment: "Pattern name")
        case .perlinNoise: String(localized: "pattern.perlin_noise", comment: "Pattern name")
        case .worleyNoise: String(localized: "pattern.worley_noise", comment: "Pattern name")
        case .voronoi: String(localized: "pattern.voronoi", comment: "Pattern name")
        case .reactionDiffusion: String(localized: "pattern.reaction_diffusion", comment: "Pattern name")
        }
    }

    var iconSystemName: String {
        switch self {
        case .randomDot: "circle.dotted"
        case .stars: "star"
        case .perlinNoise: "smoke"
        case .worleyNoise: "circle.hexagongrid"
        case .voronoi: "pentagon"
        case .reactionDiffusion: "bubbles.and.sparkles"
        }
    }

    func defaultConfig() -> ProceduralConfig {
        switch self {
        case .randomDot: .randomDot(RandomDotConfig())
        case .stars: .stars(StarsConfig())
        case .perlinNoise: .perlin(PerlinConfig())
        case .worleyNoise: .worley(WorleyConfig())
        case .voronoi: .voronoi(VoronoiConfig())
        case .reactionDiffusion: .reactionDiffusion(ReactionDiffusionConfig())
        }
    }

    func makeGenerator(config: ProceduralConfig) -> PatternGenerator {
        switch (self, config) {
        case (.randomDot, .randomDot(let c)):
            RandomDotGenerator(config: c)
        case (.stars, .stars(let c)):
            StarsGenerator(config: c)
        case (.perlinNoise, .perlin(let c)):
            PerlinNoiseGenerator(config: c)
        case (.worleyNoise, .worley(let c)):
            WorleyNoiseGenerator(config: c)
        case (.voronoi, .voronoi(let c)):
            VoronoiGenerator(config: c)
        case (.reactionDiffusion, .reactionDiffusion(let c)):
            ReactionDiffusionGenerator(config: c)
        default:
            // Type/config mismatch — use default config for this type
            makeGenerator(config: defaultConfig())
        }
    }
}

// MARK: - Procedural Config Wrapper

enum ProceduralConfig: Equatable {
    case randomDot(RandomDotConfig)
    case stars(StarsConfig)
    case perlin(PerlinConfig)
    case worley(WorleyConfig)
    case voronoi(VoronoiConfig)
    case reactionDiffusion(ReactionDiffusionConfig)
}

// MARK: - Color Mode

enum PatternColorMode: String, CaseIterable, Identifiable, Equatable {
    case blackAndWhite
    case grayscale
    case color

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .blackAndWhite: String(localized: "color_mode.bw", comment: "Color mode")
        case .grayscale: String(localized: "color_mode.grayscale", comment: "Color mode")
        case .color: String(localized: "color_mode.color", comment: "Color mode")
        }
    }
}

// MARK: - Perlin Color Mode

enum PerlinColorMode: String, CaseIterable, Identifiable, Equatable {
    case grayscale
    case hue
    case rgb

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .grayscale: String(localized: "color_mode.grayscale", comment: "Color mode")
        case .hue: String(localized: "color_mode.single_hue", comment: "Color mode")
        case .rgb: String(localized: "color_mode.rgb", comment: "Color mode")
        }
    }
}

// MARK: - Distance Function

enum DistanceFunction: String, CaseIterable, Identifiable, Equatable {
    case euclidean
    case manhattan
    case chebyshev

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .euclidean: String(localized: "distance.euclidean", comment: "Distance function")
        case .manhattan: String(localized: "distance.manhattan", comment: "Distance function")
        case .chebyshev: String(localized: "distance.chebyshev", comment: "Distance function")
        }
    }
}

// MARK: - Worley Combine Mode

enum WorleyCombineMode: String, CaseIterable, Identifiable, Equatable {
    case f1
    case f2
    case f2MinusF1

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .f1: "F1"
        case .f2: "F2"
        case .f2MinusF1: "F2−F1"
        }
    }
}

// MARK: - Voronoi Color Scheme

enum VoronoiColorScheme: String, CaseIterable, Identifiable, Equatable {
    case pastel
    case vivid
    case monochrome
    case random

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pastel: String(localized: "color_scheme.pastel", comment: "Color scheme")
        case .vivid: String(localized: "color_scheme.vivid", comment: "Color scheme")
        case .monochrome: String(localized: "color_scheme.monochrome", comment: "Color scheme")
        case .random: String(localized: "color_scheme.random", comment: "Color scheme")
        }
    }
}

// MARK: - Per-Generator Config Structs

struct RandomDotConfig: Equatable {
    var density: Float = 1.0
    var dotSize: Int = 1
    var colorMode: PatternColorMode = .color
    var seed: UInt64 = 0
}

struct StarsConfig: Equatable {
    var starCount: Int = 200
    var maxRadius: Int = 2
    var backgroundColor: CodableColor = CodableColor(red: 0.06, green: 0.06, blue: 0.16)
    var seed: UInt64 = 0
}

struct PerlinConfig: Equatable {
    var frequency: Float = 0.01
    var octaves: Int = 2
    var persistence: Float = 0.5
    var colorMode: PerlinColorMode = .rgb
    var hue: Float = 0.6
    var seed: UInt64 = 0
}

struct WorleyConfig: Equatable {
    var cellSize: Float = 30
    var distanceFunction: DistanceFunction = .euclidean
    var combineMode: WorleyCombineMode = .f1
    var invertLuminance: Bool = false
    var seed: UInt64 = 0
}

struct VoronoiConfig: Equatable {
    var cellCount: Int = 32
    var jitter: Float = 1.0
    var edgeWidth: Float = 2.0
    var colorScheme: VoronoiColorScheme = .vivid
    var seed: UInt64 = 0
}

struct ReactionDiffusionConfig: Equatable {
    var feedRate: Float = 0.037
    var killRate: Float = 0.060
    var iterations: Int = 2000
    var colorA: CodableColor = CodableColor(red: 0.1, green: 0.1, blue: 0.4)
    var colorB: CodableColor = CodableColor(red: 0.9, green: 0.8, blue: 0.2)
    var seed: UInt64 = 0
}

// MARK: - CodableColor (Equatable wrapper for color values)

struct CodableColor: Equatable {
    var red: Float
    var green: Float
    var blue: Float

    var color: Color {
        Color(red: Double(red), green: Double(green), blue: Double(blue))
    }

    init(red: Float, green: Float, blue: Float) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    init(color: Color) {
        let resolved = UIColor(color)
        var r: CGFloat = 0; var g: CGFloat = 0; var b: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: nil)
        self.red = Float(r)
        self.green = Float(g)
        self.blue = Float(b)
    }
}
