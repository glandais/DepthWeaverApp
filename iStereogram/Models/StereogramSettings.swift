import Foundation

struct StereogramSettings: Equatable {
    var stripWidth: Int = 200
    var depthAmplitude: Float = 0.3
    var invert: Bool = false
    var patternSource: PatternSource = .asset(.giraffe)
}
