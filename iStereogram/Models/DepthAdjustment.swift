import Foundation

struct DepthAdjustment: Equatable {
    /// Input range: crop the raw depth to [min, max]
    var min: Float = 0
    var max: Float = 1
    /// Output range: remap to [start, end]
    var start: Float = 0
    var end: Float = 1
}
