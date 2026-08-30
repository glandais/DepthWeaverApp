import os
import SwiftUI

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "StereogramViewModel")

@MainActor
final class StereogramViewModel: ObservableObject {
    @Published var resultImage: PlatformImage?
    @Published var isGenerating = false

    private var debounceTask: Task<Void, Never>?
    private var liveTask: Task<Void, Never>?
    private var pendingLive: (depthMap: DepthMap, settings: StereogramSettings)?
    /// Renders can overlap — a coarse live frame started before the finger
    /// lifted must not land on top of the full-quality one that replaced it —
    /// so only the newest render is allowed to publish its image.
    private var renderToken = 0

    func generateDebounced(depthMap: DepthMap, settings: StereogramSettings) {
        pendingLive = nil
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await generate(depthMap: depthMap, settings: settings)
        }
    }

    /// The live path: a gesture produces frames far faster than the generator
    /// can consume them, so instead of debouncing (which would show nothing
    /// until the finger stops) only the newest frame is kept and rendered as
    /// soon as the previous one lands. Coarser output, and no spinner — the
    /// image itself is the feedback.
    func generateLive(depthMap: DepthMap, settings: StereogramSettings) {
        debounceTask?.cancel()
        pendingLive = (depthMap, settings)
        guard liveTask == nil else { return }
        liveTask = Task { [weak self] in
            while let next = self?.takePendingLive() {
                await self?.generate(
                    depthMap: next.depthMap,
                    settings: next.settings,
                    quality: .preview,
                    showsProgress: false
                )
            }
            self?.liveTask = nil
        }
    }

    /// True while a live frame is queued but not yet picked up. Callers whose
    /// *input* is expensive to produce — live 3D re-renders the scene into a
    /// depth buffer before it can ask for a stereogram — use this to skip work
    /// the generator would only throw away.
    var hasPendingLiveFrame: Bool { pendingLive != nil }

    /// Drops the queued live frame — the canvas calls this when it leaves live
    /// mode so a stale coarse render can't land on top of the full-quality one.
    func cancelLive() {
        pendingLive = nil
    }

    private func takePendingLive() -> (depthMap: DepthMap, settings: StereogramSettings)? {
        defer { pendingLive = nil }
        return pendingLive
    }

    func generate(
        depthMap: DepthMap,
        settings: StereogramSettings,
        quality: StereogramQuality = .full,
        showsProgress: Bool = true
    ) async {
        renderToken &+= 1
        let token = renderToken
        if showsProgress { isGenerating = true }
        let generator = StereogramGenerator()
        let start = CFAbsoluteTimeGetCurrent()
        let image = await Task.detached(priority: .userInitiated) {
            generator.generate(depthMap: depthMap, settings: settings, quality: quality)
        }.value
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        logger.info("Stereogram generated in \(String(format: "%.2f", elapsed))s")
        guard token == renderToken else { return }
        resultImage = image
        isGenerating = false
    }
}
