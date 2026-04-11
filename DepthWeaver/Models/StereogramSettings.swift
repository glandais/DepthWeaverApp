import Foundation

enum MainStripePosition: String, CaseIterable, Identifiable, Equatable {
    case left
    case middle

    var id: String { rawValue }
}

struct StereogramSettings: Equatable {
    var stripesCount: Int = 8
    var depthFactor: Float = 0.8
    var mainStripePosition: MainStripePosition = .middle
    var invert: Bool = false
    var patternSource: PatternSource = .asset(.giraffe)
}
