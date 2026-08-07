import os
import SwiftUI

#if os(iOS)
import ARKit
import PhotosUI
import RealityKit
#endif

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "ContentView")

/// Shared state that persists across navigation destinations.
@MainActor
final class AppState: ObservableObject {
    @Published var currentDepthMap: DepthMap? = DepthMapPreset.dog.toDepthMap()
    @Published var resultImage: PlatformImage?
    @Published var showHelp = false

    #if os(iOS)
    @Published var pendingCapture: PendingCapture?
    /// Set after a fresh scan is saved into the library; consumed by
    /// `Model3DCaptureView` on first appearance to auto-load the new model.
    @Published var pendingModel3DLoadID: UUID?
    let lidarService = LiDARDepthService()
    let capturedLibrary = CapturedModelLibrary.shared
    #endif

    func reset() {
        currentDepthMap = DepthMapPreset.dog.toDepthMap()
        resultImage = nil
    }
}

#if os(iOS)
/// A freshly produced `.usdz` waiting to be named and saved into the captured-model library.
struct PendingCapture: Identifiable, Hashable {
    let id = UUID()
    let url: URL
}
#endif

struct ContentView: View {
    @StateObject private var appState = AppState()

    var body: some View {
        #if os(iOS)
        IOSContentView(appState: appState)
        #elseif os(macOS)
        MacGenerationView()
            .environmentObject(appState)
            .frame(minWidth: 900, minHeight: 700)
        #endif
    }
}

#if os(iOS)
struct IOSContentView: View {
    @ObservedObject var appState: AppState
    @State private var path = NavigationPath()
    @StateObject private var photoDepthVM = PhotoDepthViewModel()

    private var guidedCaptureSupported: Bool {
        if #available(iOS 17.0, *) {
            return ObjectCaptureSession.isSupported && PhotogrammetrySession.isSupported
        }
        return false
    }

    var body: some View {
        NavigationStack(path: $path) {
            CanvasScreen(
                depthMap: $appState.currentDepthMap,
                path: $path
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
                case .depthSource:
                    DepthSourceScreen(
                        depthMap: $appState.currentDepthMap,
                        path: $path,
                        photoDepthVM: photoDepthVM,
                        lidarAvailable: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
                        guidedCaptureSupported: guidedCaptureSupported
                    )
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
        .preferredColorScheme(.dark)
        .tint(DWColor.cyan)
    }
}

enum NavigationDestination: Hashable {
    case lidarCapture
    case model3DCapture
    case guidedCapture
    case stereogramResult(PlatformImage)
    case depthAdjustment
    case depthSource

    func hash(into hasher: inout Hasher) {
        switch self {
        case .lidarCapture: hasher.combine(0)
        case .model3DCapture: hasher.combine(1)
        case .guidedCapture: hasher.combine(4)
        case .stereogramResult: hasher.combine(2)
        case .depthAdjustment: hasher.combine(3)
        case .depthSource: hasher.combine(5)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.lidarCapture, .lidarCapture): true
        case (.model3DCapture, .model3DCapture): true
        case (.guidedCapture, .guidedCapture): true
        case (.stereogramResult, .stereogramResult): true
        case (.depthAdjustment, .depthAdjustment): true
        case (.depthSource, .depthSource): true
        default: false
        }
    }
}
#endif
