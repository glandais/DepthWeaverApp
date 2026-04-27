import os
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.glandais.DepthWeaver", category: "Model3DCaptureView")

struct Model3DCaptureView: View {
    let onCapture: (DepthMap) -> Void

    @StateObject private var viewModel = Model3DCaptureViewModel()
    @State private var sceneViewHolder = SceneViewHolder()
    @State private var showFileImporter = false
    @State private var showPresetSheet = false

    var body: some View {
        VStack(spacing: 0) {
            sceneArea
            Divider()
            controls
        }
        .navigationTitle("model3d.capture_title")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showFileImporter = true
                    } label: {
                        Label("model3d.open_file", systemImage: "folder")
                    }
                    Button {
                        showPresetSheet = true
                    } label: {
                        Label("model3d.presets", systemImage: "square.grid.2x2")
                    }
                } label: {
                    Image(systemName: "plus.circle")
                }
            }
        }
        .sheet(isPresented: $showPresetSheet) {
            Model3DPresetSheet(selectedID: viewModel.selectedPresetID) { preset in
                showPresetSheet = false
                Task { await viewModel.loadPreset(preset) }
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: Self.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task { await viewModel.loadFile(url: url) }
            case .failure(let error):
                logger.error("fileImporter failed: \(error.localizedDescription)")
            }
        }
        .alert("general.error", isPresented: $viewModel.showError) {
            Button("general.ok") {}
        } message: {
            Text(viewModel.loadErrorMessage ?? "")
        }
        .overlay {
            if viewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView()
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    private static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.usdz]
        if let usd = UTType(filenameExtension: "usd") { types.append(usd) }
        if let usda = UTType(filenameExtension: "usda") { types.append(usda) }
        if let usdc = UTType(filenameExtension: "usdc") { types.append(usdc) }
        if let obj = UTType(filenameExtension: "obj") { types.append(obj) }
        if let scn = UTType(filenameExtension: "scn") { types.append(scn) }
        return types
    }

    @ViewBuilder
    private var sceneArea: some View {
        ZStack {
            if let scene = viewModel.scene {
                Model3DSceneView(scene: scene, holder: sceneViewHolder)
                    .background(Color.black)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("model3d.empty_state_title")
                .font(.title3)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)

            Text("model3d.empty_state_message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 12) {
                Button {
                    showFileImporter = true
                } label: {
                    Label("model3d.open_file", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showPresetSheet = true
                } label: {
                    Label("model3d.presets", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
    }

    private var controls: some View {
        VStack(spacing: 8) {
            if let label = viewModel.sourceLabel {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Button {
                captureDepth()
            } label: {
                Label("model3d.capture_depth", systemImage: "camera.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.scene == nil)
        }
        .padding()
        .background(.regularMaterial)
    }

    private func captureDepth() {
        guard let scnView = sceneViewHolder.scnView else {
            logger.error("captureDepth: no SCNView available")
            return
        }
        let size = scnView.bounds.size
        guard size.width > 0, size.height > 0 else {
            logger.error("captureDepth: invalid SCNView size")
            return
        }
        guard let depthMap = Model3DDepthRenderer.captureDepthMap(from: scnView, outputSize: size) else {
            logger.error("captureDepth: renderer returned nil")
            return
        }
        onCapture(depthMap)
    }
}

// MARK: - SCNView wrapper

/// Holds a weak reference to the underlying SCNView so the capture pipeline can
/// read its current pointOfView and bounds at the moment of capture. All access
/// happens on the main thread (UIViewRepresentable callbacks + SwiftUI button
/// actions), so no isolation annotation is needed.
final class SceneViewHolder {
    weak var scnView: SCNView?
}

struct Model3DSceneView: UIViewRepresentable {
    let scene: SCNScene
    let holder: SceneViewHolder

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .black
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.scene = scene
        holder.scnView = view
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if uiView.scene !== scene {
            uiView.scene = scene
            // SceneKit's default camera controller picks up the scene's existing
            // camera; no extra wiring needed.
        }
        holder.scnView = uiView
    }
}

// MARK: - Preset sheet

struct Model3DPresetSheet: View {
    @Environment(\.dismiss) private var dismiss
    let selectedID: String?
    let onSelect: (Model3DPreset) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Model3DPreset.allCases) { preset in
                        Button {
                            onSelect(preset)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: preset.systemImageName)
                                    .font(.system(size: 36))
                                    .frame(width: 90, height: 90)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.2))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedID == preset.id ? Color.accentColor : .clear, lineWidth: 2)
                                    )

                                Text(preset.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("model3d.presets_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("general.done") { dismiss() }
                }
            }
        }
    }
}
