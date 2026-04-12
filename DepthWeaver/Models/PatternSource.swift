import UIKit

enum PatternSource: Identifiable, Equatable {
    case asset(StereogramPattern)
    case procedural(ProceduralPatternType, ProceduralConfig)
    case imported(UIImage)

    var id: String {
        switch self {
        case .asset(let pattern):
            "asset-\(pattern.id)"
        case .procedural(let type, _):
            "procedural-\(type.id)"
        case .imported:
            "imported"
        }
    }

    var displayName: String {
        switch self {
        case .asset(let pattern):
            pattern.displayName
        case .procedural(let type, _):
            type.displayName
        case .imported:
            String(localized: "depth.source_imported", comment: "Pattern name")
        }
    }

    func generateImage(size: CGSize) -> UIImage {
        switch self {
        case .asset(let pattern):
            pattern.loadImage()
        case .procedural(let type, let config):
            type.makeGenerator(config: config).generate(size: size)
        case .imported(let image):
            image
        }
    }

    static func == (lhs: PatternSource, rhs: PatternSource) -> Bool {
        switch (lhs, rhs) {
        case (.asset(let a), .asset(let b)):
            a == b
        case (.procedural(let tA, let cA), .procedural(let tB, let cB)):
            tA == tB && cA == cB
        case (.imported(let a), .imported(let b)):
            a === b
        default:
            false
        }
    }
}
