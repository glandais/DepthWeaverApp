import SwiftUI

@MainActor
final class StereogramViewModel: ObservableObject {
    @Published var resultImage: UIImage?
    @Published var isGenerating = false

    func generate(depthMap: DepthMap, settings: StereogramSettings) async {
        isGenerating = true
        let generator = StereogramGenerator()
        let image = await Task.detached(priority: .userInitiated) {
            generator.generate(depthMap: depthMap, settings: settings)
        }.value
        resultImage = image
        isGenerating = false
    }
}
