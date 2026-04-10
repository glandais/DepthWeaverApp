import UIKit

enum PatternSource: Identifiable, Equatable {
    case asset(StereogramPattern)
    case procedural(ProceduralPatternType, ProceduralConfig)

    var id: String {
        switch self {
        case .asset(let pattern):
            "asset-\(pattern.id)"
        case .procedural(let type, _):
            "procedural-\(type.id)"
        }
    }

    var displayName: String {
        switch self {
        case .asset(let pattern):
            pattern.displayName
        case .procedural(let type, _):
            type.displayName
        }
    }

    func generateImage(size: CGSize) -> UIImage {
        switch self {
        case .asset(let pattern):
            pattern.loadImage()
        case .procedural(let type, let config):
            type.makeGenerator(config: config).generate(size: size)
        }
    }
}
