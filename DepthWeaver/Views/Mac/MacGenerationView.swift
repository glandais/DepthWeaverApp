#if os(macOS)
import AppKit
import os
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "io.github.glandais.depthweaver", category: "MacGenerationView")

struct MacGenerationView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var stereogramVM = StereogramViewModel()
    @StateObject private var patternPreviewVM = PatternPreviewViewModel()
    @StateObject private var photoDepthVM = PhotoDepthViewModel()
    @StateObject private var sceneVM = Model3DCaptureViewModel()

    @State private var settings = StereogramSettings()
    @State private var inspectorVisible = true
    @State private var showImporter = false
    @State private var showSaveExporter = false
    @State private var showPatternImporter = false
    @State private var showSceneSheet = false

    @State private var saveDocument: StereogramPNGDocument?

    var body: some View {
        HSplitView {
            canvas
                .frame(minWidth: 400)

            if inspectorVisible {
                InspectorPanel(
                    settings: $settings,
                    depthMap: $appState.currentDepthMap,
                    patternPreview: patternPreviewVM,
                    onPickPhoto: { showImporter = true },
                    onPick3DModel: { showSceneSheet = true },
                    onPickPattern: { showPatternImporter = true }
                )
                .frame(minWidth: 280, idealWidth: 340, maxWidth: 480)
            }
        }
        .toolbar { toolbarContent }
        .navigationTitle("DepthWeaver")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: Self.openContentTypes,
            allowsMultipleSelection: false,
            onCompletion: handleOpen
        )
        .fileImporter(
            isPresented: $showPatternImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false,
            onCompletion: handlePatternImport
        )
        .fileExporter(
            isPresented: $showSaveExporter,
            document: saveDocument,
            contentType: .png,
            defaultFilename: "DepthWeaver"
        ) { result in
            if case .failure(let error) = result {
                logger.error("save failed: \(error.localizedDescription)")
            }
        }
        .sheet(isPresented: $showSceneSheet) {
            SceneCaptureSheet(viewModel: sceneVM, onCapture: handleSceneCapture)
                .frame(minWidth: 700, minHeight: 520)
        }
        .sheet(isPresented: $appState.showHelp) {
            HelpSheet()
        }
        .alert("general.error", isPresented: $photoDepthVM.showError) {
            Button("general.ok") {}
        } message: {
            Text(photoDepthVM.errorMessage)
        }
        .alert("general.error", isPresented: $sceneVM.showError) {
            Button("general.ok") {}
        } message: {
            Text(sceneVM.loadErrorMessage ?? "")
        }
        .onAppear {
            triggerGeneration()
        }
        .onChange(of: appState.currentDepthMap?.id) { _, _ in triggerGeneration() }
        .onChange(of: appState.currentDepthMap?.adjustment) { _, _ in triggerGeneration() }
        .onChange(of: settings) { _, _ in
            triggerGeneration()
            updatePatternPreview()
        }
        .onChange(of: stereogramVM.resultImage) { _, newValue in
            appState.resultImage = newValue
        }
        .onReceive(NotificationCenter.default.publisher(for: .depthWeaverOpenRequested)) { _ in
            showImporter = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .depthWeaverSaveRequested)) { _ in
            triggerSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .depthWeaverCopyRequested)) { _ in
            copyResultToPasteboard()
        }
        .onReceive(NotificationCenter.default.publisher(for: .depthWeaverToggleInspector)) { _ in
            withAnimation(.smooth(duration: 0.2)) { inspectorVisible.toggle() }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                showImporter = true
            } label: {
                Label("toolbar.open", systemImage: "folder")
            }
            .help(Text("toolbar.open.help"))

            Button {
                triggerSave()
            } label: {
                Label("toolbar.save", systemImage: "square.and.arrow.down")
            }
            .disabled(stereogramVM.resultImage == nil)
            .help(Text("toolbar.save.help"))

            if let image = stereogramVM.resultImage {
                ShareLink(
                    item: Image(platformImage: image),
                    preview: SharePreview(String(localized: "result.title"), image: Image(platformImage: image))
                ) {
                    Label("toolbar.share", systemImage: "square.and.arrow.up")
                }
                .help(Text("toolbar.share.help"))
            }

            Spacer()

            Button {
                withAnimation(.smooth(duration: 0.2)) { inspectorVisible.toggle() }
            } label: {
                Label("toolbar.inspector", systemImage: "sidebar.right")
            }
            .help(Text("toolbar.inspector.help"))

            Button {
                appState.showHelp = true
            } label: {
                Label("help.how_to_use_button", systemImage: "questionmark.circle")
            }
            .help(Text("help.how_to_use_button"))
        }
    }

    @ViewBuilder
    private var canvas: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()

            if let image = stereogramVM.resultImage {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(20)
                    .overlay {
                        if stereogramVM.isGenerating {
                            ProgressView().scaleEffect(1.4)
                                .padding(20)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
            } else if appState.currentDepthMap != nil {
                ProgressView("generation.generating")
            } else {
                placeholder
            }

            if photoDepthVM.isProcessing {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("depth.estimating")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            handleDroppedURL(url)
            return true
        }
    }

    private var placeholder: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("mac.canvas.placeholder")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showImporter = true
            } label: {
                Label("toolbar.open", systemImage: "folder")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private static var openContentTypes: [UTType] {
        var types: [UTType] = [.image, .usdz]
        if let usd = UTType(filenameExtension: "usd") { types.append(usd) }
        if let usda = UTType(filenameExtension: "usda") { types.append(usda) }
        if let usdc = UTType(filenameExtension: "usdc") { types.append(usdc) }
        if let obj = UTType(filenameExtension: "obj") { types.append(obj) }
        if let scn = UTType(filenameExtension: "scn") { types.append(scn) }
        return types
    }

    private static let model3DExtensions: Set<String> = [
        "usdz", "usd", "usda", "usdc", "obj", "scn",
    ]

    private func handleOpen(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            handleDroppedURL(url)
        case .failure(let error):
            logger.error("open failed: \(error.localizedDescription)")
        }
    }

    private func handleDroppedURL(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if Self.model3DExtensions.contains(ext) {
            Task {
                await sceneVM.loadFile(url: url)
                if sceneVM.scene != nil {
                    showSceneSheet = true
                }
            }
        } else {
            Task {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                let _ = await processDepthFromURL(url)
            }
        }
    }

    private func processDepthFromURL(_ url: URL) async -> Bool {
        // Heightmap path: load directly as DepthMap. Otherwise use AI estimation.
        guard let data = try? Data(contentsOf: url),
              let cgSource = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(cgSource, 0, nil) != nil
        else { return false }

        // Heuristic: if the file is grayscale and small (< 1024 either dim), treat as heightmap
        let props = CGImageSourceCopyPropertiesAtIndex(cgSource, 0, nil) as? [CFString: Any]
        let colorModel = props?[kCGImagePropertyColorModel] as? String
        let isGray = colorModel == (kCGImagePropertyColorModelGray as String)

        if isGray, let img = PlatformImage(contentsOf: url) {
            let dm = await Task.detached(priority: .userInitiated) {
                DepthMap(image: img)
            }.value
            appState.currentDepthMap = dm
            return true
        }

        await photoDepthVM.processImage(data: data)
        if let dm = photoDepthVM.depthMap {
            appState.currentDepthMap = dm
            return true
        }
        return false
    }

    private func handlePatternImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first,
                  let img = PlatformImage(contentsOf: url) else { return }
            settings.patternSource = .imported(img)
        case .failure(let error):
            logger.error("pattern import failed: \(error.localizedDescription)")
        }
    }

    private func handleSceneCapture(_ depthMap: DepthMap) {
        appState.currentDepthMap = depthMap
        showSceneSheet = false
    }

    private func triggerGeneration() {
        guard let depthMap = appState.currentDepthMap else {
            stereogramVM.resultImage = nil
            return
        }
        stereogramVM.generateDebounced(depthMap: depthMap, settings: settings)
    }

    private func updatePatternPreview() {
        if case .procedural = settings.patternSource {
            patternPreviewVM.updatePreview(source: settings.patternSource)
        }
    }

    private func triggerSave() {
        guard let image = stereogramVM.resultImage,
              let data = image.pngData() else { return }
        saveDocument = StereogramPNGDocument(data: data)
        showSaveExporter = true
    }

    private func copyResultToPasteboard() {
        guard let image = stereogramVM.resultImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }
}

// MARK: - Pasteboard helpers

extension Notification.Name {
    static let depthWeaverOpenRequested = Notification.Name("DepthWeaver.OpenRequested")
    static let depthWeaverSaveRequested = Notification.Name("DepthWeaver.SaveRequested")
    static let depthWeaverCopyRequested = Notification.Name("DepthWeaver.CopyRequested")
    static let depthWeaverToggleInspector = Notification.Name("DepthWeaver.ToggleInspector")
}

// MARK: - PlatformImage URL helper

private extension PlatformImage {
    convenience init?(contentsOf url: URL) {
        self.init(contentsOfFile: url.path)
    }
}
#endif
