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

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = Model3DCaptureViewModel()
    @State private var sceneViewHolder = SceneViewHolder()
    @State private var showFileImporter = false
    @State private var showPresetSheet = false
    @State private var renamingEntry: CapturedModelLibrary.Entry?

    var body: some View {
        VStack(spacing: 0) {
            header
            sceneArea
            Rectangle()
                .fill(DWColor.hairline)
                .frame(height: 1)
            controls
        }
        .background(DWColor.ground)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // If we were navigated here right after a fresh scan was saved,
            // auto-load that capture so the user lands on the depth-capture
            // view with their model already set up.
            if let id = pendingAutoLoadID {
                pendingAutoLoadID = nil
                await viewModel.loadCapturedModel(id: id, library: library)
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
                    DWColor.ground.opacity(0.55).ignoresSafeArea()
                    ProgressView()
                        .tint(DWColor.cyan)
                        .padding(DWSpace.xxl)
                        .dwGlass(radius: DWRadius.xl)
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

    private var header: some View {
        HStack(spacing: DWSpace.m) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(DWCircleGlassButtonStyle(size: 34))
            .accessibilityLabel("general.back")

            Text("model3d.capture_title")
                .font(DWFont.screenTitle)
                .foregroundStyle(DWColor.text)

            Spacer(minLength: 0)

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
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DWColor.text)
                    .frame(width: 34, height: 34)
                    .dwGlassCircle()
            }
            .accessibilityLabel("model3d.menu.add_model")
        }
        .padding(.horizontal, DWSpace.l)
        .padding(.top, DWSpace.s)
        .padding(.bottom, DWSpace.m)
    }

    @ViewBuilder
    private var sceneArea: some View {
        ZStack {
            if let scene = viewModel.scene {
                Model3DSceneView(scene: scene, holder: sceneViewHolder)
                    .background(DWColor.ground)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Three side-by-side buttons shattered into four lines each in French, so
    /// the actions are stacked rows — the same grouped list the depth-source
    /// screen offers its capture flows in.
    private var emptyState: some View {
        VStack(spacing: DWSpace.l) {
            Spacer(minLength: 0)

            DWIconTile(systemImage: "cube.transparent", tint: DWColor.periwinkle, size: 64)

            VStack(spacing: DWSpace.s) {
                Text("model3d.empty_state_title")
                    .font(DWFont.heroTitle)
                    .foregroundStyle(DWColor.text)

                Text("model3d.empty_state_message")
                    .font(DWFont.body)
                    .foregroundStyle(DWColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: 320)

            DWGroupedList {
                if guidedCaptureSupported {
                    DWListRow(
                        title: "model3d.menu.capture_new",
                        systemImage: "camera.viewfinder"
                    ) {
                        onRequestCapture()
                    }
                    DWSeparator(leadingInset: 60)
                }

                DWListRow(
                    title: "model3d.open_file",
                    systemImage: "folder",
                    tint: DWColor.text
                ) {
                    showFileImporter = true
                }
                DWSeparator(leadingInset: 60)

                DWListRow(
                    title: "model3d.presets",
                    systemImage: "square.grid.2x2",
                    tint: DWColor.periwinkle
                ) {
                    showPresetSheet = true
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DWSpace.l)
        .padding(.vertical, DWSpace.xl)
    }

    private var controls: some View {
        VStack(spacing: DWSpace.s) {
            if let label = viewModel.sourceLabel {
                Text(label)
                    .font(DWFont.valueMono)
                    .foregroundStyle(DWColor.textSecondary)
                    .lineLimit(1)
            }
            Button {
                captureDepth()
            } label: {
                Label("model3d.capture_depth", systemImage: "camera.viewfinder")
            }
            .buttonStyle(DWPrimaryButtonStyle(height: 52))
            .disabled(viewModel.scene == nil)
            // Desaturated rather than faded: a translucent cyan over the bar
            // reads as a washed-out slab instead of an unavailable action.
            .saturation(viewModel.scene == nil ? 0 : 1)
            .opacity(viewModel.scene == nil ? 0.45 : 1)
        }
        .padding(.horizontal, DWSpace.l)
        .padding(.top, DWSpace.m)
        .padding(.bottom, DWSpace.l)
        .background(DWColor.surface)
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
        view.backgroundColor = UIColor(DWColor.ground)
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
        GridItem(.adaptive(minimum: 100), spacing: DWSpace.m)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DWSpace.xl) {
                    capturesSection
                    bundledSection
                }
                .padding(DWSpace.l)
            }
            .background(DWColor.ground)
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
        VStack(alignment: .leading, spacing: DWSpace.s) {
            DWSectionLabel("model3d.section.my_captures")

            if library.entries.isEmpty {
                VStack(spacing: DWSpace.s) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 30))
                        .foregroundStyle(DWColor.textTertiary)
                    Text("model3d.captures.empty")
                        .font(DWFont.ui(12))
                        .foregroundStyle(DWColor.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DWSpace.xl)
                .dwGlass(radius: DWRadius.lg)
            } else {
                LazyVGrid(columns: columns, spacing: DWSpace.l) {
                    ForEach(library.entries) { entry in
                        Button {
                            onSelectCaptured(entry.id)
                        } label: {
                            modelTile(
                                systemImage: "cube.transparent",
                                title: entry.displayName,
                                isSelected: selectedCapturedID == entry.id
                            )
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
        VStack(alignment: .leading, spacing: DWSpace.s) {
            DWSectionLabel("model3d.section.bundled")

            LazyVGrid(columns: columns, spacing: DWSpace.l) {
                ForEach(Model3DPreset.allCases) { preset in
                    Button {
                        onSelectPreset(preset)
                    } label: {
                        modelTile(
                            systemImage: preset.systemImageName,
                            title: preset.displayName,
                            isSelected: selectedPresetID == preset.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func modelTile(systemImage: String, title: String, isSelected: Bool) -> some View {
        VStack(spacing: DWSpace.s) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(isSelected ? DWColor.cyan : DWColor.text)
                .frame(maxWidth: .infinity)
                .frame(height: 74)

            Text(title)
                .font(DWFont.caption)
                .foregroundStyle(DWColor.textSecondary)
                .lineLimit(1)
        }
        .padding(DWSpace.s)
        .dwGlass(radius: DWRadius.lg)
        .overlay {
            RoundedRectangle(cornerRadius: DWRadius.lg, style: .continuous)
                .stroke(isSelected ? DWColor.cyan : .clear, lineWidth: 1.5)
        }
    }
}

#endif
