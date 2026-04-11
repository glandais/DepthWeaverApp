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
        case .dog: String(localized: "Dog", comment: "Depth map preset")
        case .planet: String(localized: "Planet", comment: "Depth map preset")
        case .ship: String(localized: "Ship", comment: "Depth map preset")
        case .dolphin: String(localized: "Dolphin", comment: "Depth map preset")
        case .island: String(localized: "Island", comment: "Depth map preset")
        case .atomium: String(localized: "Atomium", comment: "Depth map preset")
        case .hand: String(localized: "Hand", comment: "Depth map preset")
        case .sphinx: String(localized: "Sphinx", comment: "Depth map preset")
        case .head: String(localized: "Head", comment: "Depth map preset")
        case .tree: String(localized: "Tree", comment: "Depth map preset")
        case .car: String(localized: "Car", comment: "Depth map preset")
        case .thumbsUp: String(localized: "Thumbs Up", comment: "Depth map preset")
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
