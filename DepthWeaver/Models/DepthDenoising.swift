import Foundation

struct DepthDenoising: Equatable {
    var enabled: Bool = false
    var bilateralIntensity: Float = 0.4
    var morphologyRadius: Float = 3
    var backgroundThreshold: Float = 0.05

    static var defaultsForImported: DepthDenoising {
        DepthDenoising(
            enabled: true,
            bilateralIntensity: 0.4,
            morphologyRadius: 3,
            backgroundThreshold: 0.05
        )
    }
}
