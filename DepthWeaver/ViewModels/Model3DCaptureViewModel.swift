import os
import SceneKit
import SwiftUI

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "Model3DCaptureViewModel")

@MainActor
final class Model3DCaptureViewModel: ObservableObject {
    @Published var scene: SCNScene?
    @Published var sourceLabel: String?
    @Published var isLoading = false
    @Published var loadErrorMessage: String?
    @Published var showError = false
    @Published var selectedPresetID: String?
    @Published var selectedCapturedID: UUID?

    func loadFile(url: URL) async {
        isLoading = true
        defer { isLoading = false }

        let didStartAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try Model3DLoader.loadScene(from: url)
            }.value
            scene = loaded
            sourceLabel = url.lastPathComponent
            selectedPresetID = nil
            selectedCapturedID = nil
        } catch {
            logger.error("loadFile failed: \(error.localizedDescription)")
            present(error: error)
        }
    }

    func loadPreset(_ preset: Model3DPreset) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try preset.loadScene()
            }.value
            scene = loaded
            sourceLabel = preset.displayName
            selectedPresetID = preset.id
            selectedCapturedID = nil
        } catch {
            logger.error("loadPreset failed: \(error.localizedDescription)")
            present(error: error)
        }
    }

    #if os(iOS)
    func loadCapturedModel(id: UUID, library: CapturedModelLibrary = .shared) async {
        guard let url = library.url(for: id), let entry = library.entry(for: id) else {
            present(error: NSError(domain: "CapturedModelLibrary", code: -1))
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try Model3DLoader.loadScene(from: url)
            }.value
            scene = loaded
            sourceLabel = entry.displayName
            selectedPresetID = nil
            selectedCapturedID = id
        } catch {
            logger.error("loadCapturedModel failed: \(error.localizedDescription)")
            present(error: error)
        }
    }
    #endif

    private func present(error: Error) {
        loadErrorMessage = String(localized: "model3d.load_failed", comment: "Generic load failure")
        showError = true
    }
}
