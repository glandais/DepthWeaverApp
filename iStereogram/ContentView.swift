import ARKit
import os
import PhotosUI
import SwiftUI

private let logger = Logger(subsystem: "com.glandais.iStereogram", category: "ContentView")

/// Shared state that persists across navigation destinations.
@MainActor
final class AppState: ObservableObject {
    @Published var currentDepthMap: DepthMap?
    let lidarService = LiDARDepthService()
}

struct ContentView: View {
    @State private var path = NavigationPath()
    @State private var selectedPhoto: PhotosPickerItem?
    @StateObject private var appState = AppState()
    @StateObject private var photoDepthVM = PhotoDepthViewModel()

    var body: some View {
        NavigationStack(path: $path) {
            GenerationView(
                depthMap: appState.currentDepthMap,
                path: $path,
                selectedPhoto: $selectedPhoto,
                lidarAvailable: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
            )
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .lidarCapture:
                    LiDARCaptureView(depthService: appState.lidarService, onCapture: { depthMap in
                        logger.info("onCapture called, depthMap \(depthMap.width)x\(depthMap.height)")
                        appState.currentDepthMap = depthMap
                        path.removeLast()
                    })
                case .stereogramResult(let image):
                    StereogramResultView(image: image)
                }
            }
            .overlay {
                if photoDepthVM.isProcessing {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView("Estimating depth...")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.3), value: photoDepthVM.isProcessing)
            .onChange(of: selectedPhoto) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    await photoDepthVM.processPhoto(item: item)
                    selectedPhoto = nil
                    if let depthMap = photoDepthVM.depthMap {
                        appState.currentDepthMap = depthMap
                    }
                }
            }
            .alert("Error", isPresented: $photoDepthVM.showError) {
                Button("OK") {}
            } message: {
                Text(photoDepthVM.errorMessage)
            }
        }
    }
}

enum NavigationDestination: Hashable {
    case lidarCapture
    case stereogramResult(UIImage)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .lidarCapture: hasher.combine(0)
        case .stereogramResult: hasher.combine(2)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.lidarCapture, .lidarCapture): true
        case (.stereogramResult, .stereogramResult): true
        default: false
        }
    }
}
