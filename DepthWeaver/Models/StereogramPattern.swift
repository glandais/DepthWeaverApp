import Foundation

enum StereogramPattern: String, CaseIterable, Identifiable {
    case noise
    case dots
    case circles
    case triangles
    case mosaic
    case stars
    case hexagons
    case space
    case wallpaper
    case clouds
    case stones
    case foliage
    case giraffe
    case leaves

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noise: String(localized: "pattern.noise", comment: "Pattern name")
        case .dots: String(localized: "pattern.dots", comment: "Pattern name")
        case .circles: String(localized: "pattern.circles", comment: "Pattern name")
        case .triangles: String(localized: "pattern.triangles", comment: "Pattern name")
        case .mosaic: String(localized: "pattern.mosaic", comment: "Pattern name")
        case .stars: String(localized: "pattern.stars", comment: "Pattern name")
        case .hexagons: String(localized: "pattern.hexagons", comment: "Pattern name")
        case .space: String(localized: "pattern.space", comment: "Pattern name")
        case .wallpaper: String(localized: "pattern.wallpaper", comment: "Pattern name")
        case .clouds: String(localized: "pattern.clouds", comment: "Pattern name")
        case .stones: String(localized: "pattern.stones", comment: "Pattern name")
        case .foliage: String(localized: "pattern.foliage", comment: "Pattern name")
        case .giraffe: String(localized: "pattern.giraffe", comment: "Pattern name")
        case .leaves: String(localized: "pattern.leaves", comment: "Pattern name")
        }
    }

    var fileName: String {
        "pattern-\(rawValue)"
    }

    func loadImage() -> PlatformImage {
        if let image = PlatformImage.loadFromAssets(named: fileName) {
            return image
        }
        if let image = PlatformImage.loadFromBundle(name: fileName, ofType: "png") {
            return image
        }
        fatalError("Missing pattern asset: \(fileName).png")
    }
}
