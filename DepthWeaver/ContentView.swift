import ARKit
import os
import PhotosUI
import RealityKit
import SwiftUI

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "ContentView")

/// Shared state that persists across navigation destinations.
@MainActor
final class AppState: ObservableObject {
    @Published var currentDepthMap: DepthMap? = DepthMapPreset.dog.toDepthMap()
    @Published var pendingCapture: PendingCapture?
    /// Set after a fresh scan is saved into the library; consumed by
    /// `Model3DCaptureView` on first appearance to auto-load the new model.
    @Published var pendingModel3DLoadID: UUID?
    let lidarService = LiDARDepthService()
    let capturedLibrary = CapturedModelLibrary.shared
}

/// A freshly produced `.usdz` waiting to be named and saved into the captured-model library.
struct PendingCapture: Identifiable, Hashable {
    let id = UUID()
    let url: URL
}

struct ContentView: View {
    @State private var path = NavigationPath()
    @State private var selectedPhoto: PhotosPickerItem?
    @StateObject private var appState = AppState()
    @StateObject private var photoDepthVM = PhotoDepthViewModel()

    private var guidedCaptureSupported: Bool {
        if #available(iOS 17.0, *) {
            return ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported
        }
        return false
    }

    var body: some View {
        NavigationStack(path: $path) {
            GenerationView(
                depthMap: $appState.currentDepthMap,
                path: $path,
                selectedPhoto: $selectedPhoto,
                lidarAvailable: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
                guidedCaptureSupported: guidedCaptureSupported
            )
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .lidarCapture:
                    LiDARCaptureView(depthService: appState.lidarService, onCapture: { depthMap in
                        logger.info("onCapture called, depthMap \(depthMap.width)x\(depthMap.height)")
                        appState.currentDepthMap = depthMap
                        path.removeLast()
                    })
                case .model3DCapture:
                    Model3DCaptureView(
                        onCapture: { depthMap in
                            logger.info("onCapture (3D) called, depthMap \(depthMap.width)x\(depthMap.height)")
                            appState.currentDepthMap = depthMap
                            path.removeLast()
                        },
                        onRequestCapture: {
                            path.append(NavigationDestination.guidedCapture)
                        },
                        guidedCaptureSupported: guidedCaptureSupported,
                        library: appState.capturedLibrary,
                        pendingAutoLoadID: $appState.pendingModel3DLoadID
                    )
                case .guidedCapture:
                    if #available(iOS 17.0, *) {
                        GuidedCaptureRootView(onCompleted: { capturedURL in
                            appState.pendingCapture = PendingCapture(url: capturedURL)
                        })
                    }
                case .stereogramResult(let image):
                    StereogramResultView(image: image)
                case .depthAdjustment:
                    if appState.currentDepthMap != nil {
                        DepthAdjustmentView(depthMap: $appState.currentDepthMap)
                    }
                }
            }
            .overlay {
                if photoDepthVM.isProcessing {
                    ZStack {
                        Color.black.opacity(0.3).ignoresSafeArea()
                        ProgressView("depth.estimating")
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
            .alert("general.error", isPresented: $photoDepthVM.showError) {
                Button("general.ok") {}
            } message: {
                Text(photoDepthVM.errorMessage)
            }
            .sheet(item: $appState.pendingCapture) { pending in
                NameCaptureSheet(
                    initialName: CapturedModelLibrary.defaultName(for: Date()),
                    onCancel: {
                        try? FileManager.default.removeItem(at: pending.url)
                        appState.pendingCapture = nil
                        if !path.isEmpty { path.removeLast() }
                    },
                    onSave: { chosenName in
                        Task {
                            let savedID = await appState.capturedLibrary.save(
                                usdzAt: pending.url,
                                displayName: chosenName
                            )
                            appState.pendingCapture = nil
                            // Pop the GuidedCapture screen.
                            if !path.isEmpty { path.removeLast() }
                            // If save succeeded, hand off to Model3DCaptureView
                            // pre-loaded with the freshly saved scan.
                            if let id = savedID {
                                appState.pendingModel3DLoadID = id
                                path.append(NavigationDestination.model3DCapture)
                            }
                        }
                    }
                )
                .interactiveDismissDisabled(true)
            }
            .task { appState.capturedLibrary.load() }
        }
    }
}

enum NavigationDestination: Hashable {
    case lidarCapture
    case model3DCapture
    case guidedCapture
    case stereogramResult(UIImage)
    case depthAdjustment

    func hash(into hasher: inout Hasher) {
        switch self {
        case .lidarCapture: hasher.combine(0)
        case .model3DCapture: hasher.combine(1)
        case .guidedCapture: hasher.combine(4)
        case .stereogramResult: hasher.combine(2)
        case .depthAdjustment: hasher.combine(3)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.lidarCapture, .lidarCapture): true
        case (.model3DCapture, .model3DCapture): true
        case (.guidedCapture, .guidedCapture): true
        case (.stereogramResult, .stereogramResult): true
        case (.depthAdjustment, .depthAdjustment): true
        default: false
        }
    }
}
