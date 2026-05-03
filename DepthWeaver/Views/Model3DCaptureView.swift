#if os(iOS)
import os
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "Model3DCaptureView")

struct Model3DCaptureView: View {
    let onCapture: (DepthMap) -> Void
    let onRequestCapture: () -> Void
    let guidedCaptureSupported: Bool

    @ObservedObject var library: CapturedModelLibrary
    @Binding var pendingAutoLoadID: UUID?

    @StateObject private var viewModel = Model3DCaptureViewModel()
    @State private var sceneViewHolder = SceneViewHolder()
    @State private var showFileImporter = false
    @State private var showPresetSheet = false
    @State private var renamingEntry: CapturedModelLibrary.Entry?

    var body: some View {
        VStack(spacing: 0) {
            sceneArea
            Divider()
            controls
        }
        .navigationTitle("model3d.capture_title")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // If we were navigated here right after a fresh scan was saved,
            // auto-load that capture so the user lands on the depth-capture
            // view with their model already set up.
            if let id = pendingAutoLoadID {
                pendingAutoLoadID = nil
                await viewModel.loadCapturedModel(id: id, library: library)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if guidedCaptureSupported {
                        Button {
                            onRequestCapture()
                        } label: {
                            Label("model3d.menu.capture_new", systemImage: "camera.viewfinder")
                        }
                    }
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
            Model3DPresetSheet(
                selectedPresetID: viewModel.selectedPresetID,
                selectedCapturedID: viewModel.selectedCapturedID,
                library: library,
                onSelectPreset: { preset in
                    showPresetSheet = false
                    Task { await viewModel.loadPreset(preset) }
                },
                onSelectCaptured: { id in
                    showPresetSheet = false
                    Task { await viewModel.loadCapturedModel(id: id, library: library) }
                },
                onRequestRename: { entry in
                    showPresetSheet = false
                    renamingEntry = entry
                },
                onDelete: { id in
                    do {
                        try library.delete(id: id)
                        if viewModel.selectedCapturedID == id {
                            viewModel.selectedCapturedID = nil
                        }
                    } catch {
                        logger.error("delete capture failed: \(error.localizedDescription)")
                    }
                }
            )
        }
        .sheet(item: $renamingEntry) { entry in
            NameCaptureSheet(
                title: "model3d.captured.rename",
                initialName: entry.displayName,
                onCancel: { renamingEntry = nil },
                onSave: { newName in
                    do {
                        try library.rename(id: entry.id, to: newName)
                    } catch {
                        logger.error("rename capture failed: \(error.localizedDescription)")
                    }
                    renamingEntry = nil
                }
            )
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
                if guidedCaptureSupported {
                    Button {
                        onRequestCapture()
                    } label: {
                        Label("model3d.menu.capture_new", systemImage: "camera.viewfinder")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Group {
                    if guidedCaptureSupported {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("model3d.open_file", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            showFileImporter = true
                        } label: {
                            Label("model3d.open_file", systemImage: "folder")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

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
    let selectedPresetID: String?
    let selectedCapturedID: UUID?
    @ObservedObject var library: CapturedModelLibrary
    let onSelectPreset: (Model3DPreset) -> Void
    let onSelectCaptured: (UUID) -> Void
    let onRequestRename: (CapturedModelLibrary.Entry) -> Void
    let onDelete: (UUID) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 110), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    capturesSection
                    bundledSection
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

    @ViewBuilder
    private var capturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("model3d.section.my_captures")
                .font(.headline)

            if library.entries.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "cube.transparent")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("model3d.captures.empty")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(library.entries) { entry in
                        Button {
                            onSelectCaptured(entry.id)
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "cube.transparent")
                                    .font(.system(size: 36))
                                    .frame(width: 90, height: 90)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color.gray.opacity(0.2))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(selectedCapturedID == entry.id ? Color.accentColor : .clear, lineWidth: 2)
                                    )

                                Text(entry.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onRequestRename(entry)
                            } label: {
                                Label("model3d.captured.rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                onDelete(entry.id)
                            } label: {
                                Label("model3d.captured.delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var bundledSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("model3d.section.bundled")
                .font(.headline)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(Model3DPreset.allCases) { preset in
                    Button {
                        onSelectPreset(preset)
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
        }
    }
}

#endif
