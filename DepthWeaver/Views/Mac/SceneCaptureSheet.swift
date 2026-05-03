#if os(macOS)
import os
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "SceneCaptureSheet")

struct SceneCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: Model3DCaptureViewModel
    let onCapture: (DepthMap) -> Void

    @State private var sceneViewHolder = SceneViewHolder()
    @State private var showFileImporter = false
    @State private var showPresetSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("model3d.capture_title")
                    .font(.headline)
                Spacer()
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
                    Label("model3d.menu.capture_new", systemImage: "ellipsis.circle")
                }
                Button("general.cancel", role: .cancel) { dismiss() }
            }
            .padding()

            Divider()

            ZStack {
                if let scene = viewModel.scene {
                    Model3DSceneView(scene: scene, holder: sceneViewHolder)
                        .background(Color.black)
                } else {
                    placeholder
                }

                if viewModel.isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                        ProgressView()
                            .padding()
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                if let label = viewModel.sourceLabel {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    captureDepth()
                } label: {
                    Label("model3d.capture_depth", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(viewModel.scene == nil)
            }
            .padding()
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
        .sheet(isPresented: $showPresetSheet) {
            Model3DPresetSheetMac(
                selectedPresetID: viewModel.selectedPresetID,
                onSelectPreset: { preset in
                    showPresetSheet = false
                    Task { await viewModel.loadPreset(preset) }
                }
            )
            .frame(minWidth: 520, minHeight: 480)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("model3d.empty_state_title")
                .font(.title3)
            Text("model3d.empty_state_message")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            HStack {
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

    private static var allowedContentTypes: [UTType] {
        var types: [UTType] = [.usdz]
        if let usd = UTType(filenameExtension: "usd") { types.append(usd) }
        if let usda = UTType(filenameExtension: "usda") { types.append(usda) }
        if let usdc = UTType(filenameExtension: "usdc") { types.append(usdc) }
        if let obj = UTType(filenameExtension: "obj") { types.append(obj) }
        if let scn = UTType(filenameExtension: "scn") { types.append(scn) }
        return types
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
        dismiss()
    }
}

final class SceneViewHolder {
    weak var scnView: SCNView?
}

struct Model3DSceneView: NSViewRepresentable {
    let scene: SCNScene
    let holder: SceneViewHolder

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.wantsLayer = true
        view.layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = true
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.scene = scene
        holder.scnView = view
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {
        if nsView.scene !== scene {
            nsView.scene = scene
        }
        holder.scnView = nsView
    }
}

struct Model3DPresetSheetMac: View {
    @Environment(\.dismiss) private var dismiss
    let selectedPresetID: String?
    let onSelectPreset: (Model3DPreset) -> Void

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("model3d.section.bundled")
                    .font(.headline)
                Spacer()
                Button("general.done") { dismiss() }
            }
            .padding()
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Model3DPreset.allCases) { preset in
                        Button {
                            onSelectPreset(preset)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: preset.systemImageName)
                                    .font(.system(size: 36))
                                    .frame(width: 90, height: 90)
                                    .background(Color.gray.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedPresetID == preset.id ? Color.accentColor : .clear, lineWidth: 2)
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
        }
    }
}
#endif
