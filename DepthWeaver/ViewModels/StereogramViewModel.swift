import os
import SwiftUI

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "StereogramViewModel")

@MainActor
final class StereogramViewModel: ObservableObject {
    @Published var resultImage: PlatformImage?
    @Published var isGenerating = false

    private var debounceTask: Task<Void, Never>?

    func generateDebounced(depthMap: DepthMap, settings: StereogramSettings) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await generate(depthMap: depthMap, settings: settings)
        }
    }

    func generate(depthMap: DepthMap, settings: StereogramSettings) async {
        isGenerating = true
        let generator = StereogramGenerator()
        let start = CFAbsoluteTimeGetCurrent()
        let image = await Task.detached(priority: .userInitiated) {
            generator.generate(depthMap: depthMap, settings: settings)
        }.value
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        logger.info("Stereogram generated in \(String(format: "%.2f", elapsed))s")
        resultImage = image
        isGenerating = false
    }
}
