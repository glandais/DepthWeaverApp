import Foundation

struct StereogramSettings: Equatable {
    var dpi: Int = 96
    var depthStrength: Float = 1.0
    var sepFactor: Float = 0.55
    var oversampling: Int = 4
    var invert: Bool = false
    var patternSource: PatternSource = .asset(.giraffe)
}
