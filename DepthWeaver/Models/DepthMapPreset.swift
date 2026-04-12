import UIKit

enum DepthMapPreset: String, CaseIterable, Identifiable {
    case dog
    case planet
    case ship
    case dolphin
    case island
    case atomium
    case hand
    case sphinx
    case head
    case tree
    case car
    case thumbsUp = "thumbs-up"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dog: String(localized: "preset.dog", comment: "Depth map preset")
        case .planet: String(localized: "preset.planet", comment: "Depth map preset")
        case .ship: String(localized: "preset.ship", comment: "Depth map preset")
        case .dolphin: String(localized: "preset.dolphin", comment: "Depth map preset")
        case .island: String(localized: "preset.island", comment: "Depth map preset")
        case .atomium: String(localized: "preset.atomium", comment: "Depth map preset")
        case .hand: String(localized: "preset.hand", comment: "Depth map preset")
        case .sphinx: String(localized: "preset.sphinx", comment: "Depth map preset")
        case .head: String(localized: "preset.head", comment: "Depth map preset")
        case .tree: String(localized: "preset.tree", comment: "Depth map preset")
        case .car: String(localized: "preset.car", comment: "Depth map preset")
        case .thumbsUp: String(localized: "preset.thumbs_up", comment: "Depth map preset")
        }
    }

    func loadImage() -> UIImage {
        let name = rawValue
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let image = UIImage(contentsOfFile: path) {
            return image
        }
        fatalError("Missing heightmap asset: \(name).png")
    }

    func toDepthMap() -> DepthMap {
        var dm = DepthMap(image: loadImage())
        dm.adjustment.start = 1
        dm.adjustment.end = 0
        return dm
    }
}
