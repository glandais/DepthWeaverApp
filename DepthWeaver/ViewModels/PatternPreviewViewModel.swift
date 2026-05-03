import os
import SwiftUI

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "PatternPreviewViewModel")

@MainActor
final class PatternPreviewViewModel: ObservableObject {
    @Published var previewImage: PlatformImage?
    @Published var isGenerating = false

    private var debounceTask: Task<Void, Never>?

    func updatePreview(source: PatternSource) {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isGenerating = true
            let size = CGSize(width: 128, height: 128)
            let start = CFAbsoluteTimeGetCurrent()
            let image = await Task.detached(priority: .userInitiated) {
                source.generateImage(size: size)
            }.value
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            logger.info("Pattern preview generated in \(String(format: "%.2f", elapsed))s")
            previewImage = image
            isGenerating = false
        }
    }

    func clear() {
        debounceTask?.cancel()
        previewImage = nil
        isGenerating = false
    }
}
