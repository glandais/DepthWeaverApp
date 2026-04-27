import Foundation
import SceneKit

enum Model3DPreset: String, CaseIterable, Identifiable {
    case chameleon = "Chameleon"
    case slide = "Slide"
    case sportsCar = "SportsCar"
    case toilet = "Toilet"
    case toyBiplace = "ToyBiplace"
    case toyCar = "ToyCar"

    var id: String { rawValue }

    /// Bundled file name (without extension).
    var resourceName: String { rawValue }

    var displayName: String {
        switch self {
        case .chameleon: String(localized: "model3d.preset.chameleon", comment: "3D model preset")
        case .slide: String(localized: "model3d.preset.slide", comment: "3D model preset")
        case .sportsCar: String(localized: "model3d.preset.sports_car", comment: "3D model preset")
        case .toilet: String(localized: "model3d.preset.toilet", comment: "3D model preset")
        case .toyBiplace: String(localized: "model3d.preset.toy_biplace", comment: "3D model preset")
        case .toyCar: String(localized: "model3d.preset.toy_car", comment: "3D model preset")
        }
    }

    var systemImageName: String {
        switch self {
        case .chameleon: "tortoise.fill"
        case .slide: "figure.child"
        case .sportsCar: "car.side.fill"
        case .toilet: "toilet.fill"
        case .toyBiplace: "airplane"
        case .toyCar: "car.fill"
        }
    }

    func loadURL() -> URL? {
        Bundle.main.url(forResource: resourceName, withExtension: "usdz")
    }

    func loadScene() throws -> SCNScene {
        guard let url = loadURL() else {
            throw Model3DLoaderError.loadFailed("Missing bundled resource: \(resourceName).usdz")
        }
        return try Model3DLoader.loadScene(from: url)
    }
}
