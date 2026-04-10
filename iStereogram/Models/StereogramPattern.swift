import UIKit

enum StereogramPattern: String, CaseIterable, Identifiable {
    case noise
    case dots
    case checkerboard
    case stripes
    case circles
    case triangles
    case waves
    case mosaic
    case stars
    case hexagons

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noise: "Noise"
        case .dots: "Dots"
        case .checkerboard: "Checkerboard"
        case .stripes: "Stripes"
        case .circles: "Circles"
        case .triangles: "Triangles"
        case .waves: "Waves"
        case .mosaic: "Mosaic"
        case .stars: "Stars"
        case .hexagons: "Hexagons"
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
