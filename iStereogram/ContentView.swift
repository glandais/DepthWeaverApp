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

    private var lidarAvailable: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 20) {
                    featureCard(
                        symbol: "camera.metering.matrix",
                        title: "LiDAR Scan",
                        subtitle: lidarAvailable
                            ? "Capture 3D depth with your device's LiDAR sensor"
                            : "Requires iPhone Pro with LiDAR",
                        disabled: !lidarAvailable
                    ) {
                        path.append(NavigationDestination.lidarCapture)
                    }

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        featureCardContent(
                            symbol: "photo.on.rectangle",
                            title: "From Photo",
                            subtitle: "Generate depth from any photo using AI"
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .navigationTitle("iStereogram")
            .navigationDestination(for: NavigationDestination.self) { destination in
                switch destination {
                case .lidarCapture:
                    LiDARCaptureView(depthService: appState.lidarService, onCapture: { depthMap in
                        logger.info("onCapture called, depthMap \(depthMap.width)x\(depthMap.height)")
                        appState.currentDepthMap = depthMap
                        path.append(NavigationDestination.depthPreview)
                    })
                case .depthPreview:
                    if let depthMap = appState.currentDepthMap {
                        let _ = logger.info("Navigating to DepthPreviewView with \(depthMap.width)x\(depthMap.height)")
                        DepthPreviewView(depthMap: depthMap, path: $path)
                    } else {
                        let _ = logger.error("currentDepthMap is nil at .depthPreview navigation!")
                        ContentUnavailableView("No depth map", systemImage: "exclamationmark.triangle", description: Text("Depth map was lost during navigation"))
                    }
                case .stereogramResult(let image):
                    let _ = logger.info("Navigating to StereogramResultView")
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
                }
            }
            .onChange(of: selectedPhoto) { _, newValue in
                guard let item = newValue else { return }
                Task {
                    await photoDepthVM.processPhoto(item: item)
                    selectedPhoto = nil
                    if let depthMap = photoDepthVM.depthMap {
                        appState.currentDepthMap = depthMap
                        path.append(NavigationDestination.depthPreview)
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

    private func featureCard(
        symbol: String,
        title: String,
        subtitle: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            featureCardContent(symbol: symbol, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1.0)
    }

    private func featureCardContent(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(.blue)
                .frame(width: 52, height: 52)
                .background(.blue.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundStyle(.tertiary)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .accessibilityElement(children: .combine)
    }
}

enum NavigationDestination: Hashable {
    case lidarCapture
    case depthPreview
    case stereogramResult(UIImage)

    func hash(into hasher: inout Hasher) {
        switch self {
        case .lidarCapture: hasher.combine(0)
        case .depthPreview: hasher.combine(1)
        case .stereogramResult: hasher.combine(2)
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.lidarCapture, .lidarCapture): true
        case (.depthPreview, .depthPreview): true
        case (.stereogramResult, .stereogramResult): true
        default: false
        }
    }
}
