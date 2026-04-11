import UIKit

enum StereogramPattern: String, CaseIterable, Identifiable {
    case noise
    case dots
    case circles
    case triangles
    case mosaic
    case stars
    case hexagons

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noise: String(localized: "Noise", comment: "Pattern name")
        case .dots: String(localized: "Dots", comment: "Pattern name")
        case .circles: String(localized: "Circles", comment: "Pattern name")
        case .triangles: String(localized: "Triangles", comment: "Pattern name")
        case .mosaic: String(localized: "Mosaic", comment: "Pattern name")
        case .stars: String(localized: "Stars", comment: "Pattern name")
        case .hexagons: String(localized: "Hexagons", comment: "Pattern name")
        }
    }

    var fileName: String {
        "pattern-\(rawValue)"
    }

    func loadImage() -> UIImage {
        if let image = UIImage(named: fileName) {
            return image
        }
        if let path = Bundle.main.path(forResource: fileName, ofType: "png"),
           let image = UIImage(contentsOfFile: path) {
            return image
        }
        fatalError("Missing pattern asset: \(fileName).png")
    }
}
