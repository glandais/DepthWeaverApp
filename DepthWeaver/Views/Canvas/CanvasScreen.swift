#if os(iOS)
import PhotosUI
import SwiftUI

/// The main screen: the stereogram *is* the interface.
///
/// Everything that used to sit above the result in a scrolling stack now floats
/// over it — an info pill, a help button, and a bar whose three chips expand
/// into ``ToolDrawer``.
struct CanvasScreen: View {
    @Binding var depthMap: DepthMap?
    @Binding var path: NavigationPath

    @State private var settings = StereogramSettings()
    @State private var drawer: DrawerState = .closed
    @State private var showHelp = false
    @State private var selectedPatternPhoto: PhotosPickerItem?
    @State private var savedToPhotos = false
    @AppStorage("canvas.hintDismissed") private var hintDismissed = false
    @AppStorage("trainer.hasSeen") private var trainerSeen = false
    @StateObject private var stereogramVM = StereogramViewModel()
    @StateObject private var patternPreviewVM = PatternPreviewViewModel()

    private let drawerAnimation = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var body: some View {
        ZStack(alignment: .bottom) {
            canvas
            floatingChrome
            if drawer.isOpen {
                ToolDrawer(
                    drawer: $drawer,
                    depthMap: $depthMap,
                    settings: $settings,
                    path: $path,
                    selectedPatternPhoto: $selectedPatternPhoto,
                    patternPreviewVM: patternPreviewVM,
                    resultImage: stereogramVM.resultImage,
                    savedToPhotos: $savedToPhotos,
                    onSave: saveToPhotos
                )
                .transition(.move(edge: .bottom))
            }
        }
        .background(DWColor.ground)
        .ignoresSafeArea(edges: .bottom)
        .toolbar(.hidden, for: .navigationBar)
        .animation(drawerAnimation, value: drawer)
        .fullScreenCover(isPresented: $showHelp) {
            LearnToSeeItView()
        }
        .onAppear {
            triggerGeneration()
            // Nobody opens a help sheet before they have failed once; offer the
            // trainer up front instead, exactly once.
            if !trainerSeen {
                trainerSeen = true
                showHelp = true
            }
        }
        .onChange(of: depthMap?.id) { _, _ in
            triggerGeneration()
        }
        .onChange(of: depthMap?.adjustment) { _, _ in
            triggerGeneration()
        }
        .onChange(of: depthMap?.denoising) { _, _ in
            triggerGeneration()
        }
        .onChange(of: settings) { _, _ in
            triggerGeneration()
            updatePatternPreview()
        }
        .onChange(of: selectedPatternPhoto) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    settings.patternSource = .imported(image)
                }
            }
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = stereogramVM.resultImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .onTapGesture {
                            guard !stereogramVM.isGenerating else { return }
                            if !hintDismissed { hintDismissed = true }
                            path.append(NavigationDestination.stereogramResult(image))
                        }
                        .accessibilityLabel("result.preview")
                        .accessibilityHint("result.tap_fullscreen")
                } else {
                    DWColor.ground
                }

                if stereogramVM.isGenerating || stereogramVM.resultImage == nil {
                    ProgressView()
                        .controlSize(.large)
                        .tint(DWColor.cyan)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(DWColor.ground.opacity(stereogramVM.resultImage == nil ? 1 : 0.45))
                        .transition(.opacity)
                }
            }
            .animation(.smooth(duration: 0.25), value: stereogramVM.isGenerating)
        }
        .ignoresSafeArea()
    }

    // MARK: - Floating chrome

    private var floatingChrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            if !drawer.isOpen {
                if !hintDismissed && stereogramVM.resultImage != nil {
                    DWHintPill(text: "canvas.tap_fullscreen_hint")
                        .padding(.bottom, DWSpace.l)
                        .transition(.opacity)
                }
                bottomBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, DWSpace.l)
        .padding(.bottom, DWSpace.s)
    }

    private var topBar: some View {
        HStack(alignment: .top, spacing: DWSpace.m) {
            Button {
                path.append(NavigationDestination.depthSource)
            } label: {
                DWPillLabel(title: depthTitle, subtitle: depthSubtitle) {
                    depthSwatch
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("canvas.change_depth_source")

            Spacer(minLength: 0)

            Button { showHelp = true } label: {
                Image(systemName: "questionmark")
            }
            .buttonStyle(DWCircleGlassButtonStyle())
            .accessibilityLabel("trainer.header")
        }
    }

    @ViewBuilder
    private var depthSwatch: some View {
        if let depthMap, let preview = depthMap.previewImage() {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DWColor.periwinkle, DWColor.cyan],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 26, height: 26)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: DWSpace.s) {
            HStack(spacing: 2) {
                ForEach(ToolTab.allCases) { tab in
                    DWToolChip(
                        title: LocalizedStringKey(String(localized: tab.title)),
                        systemImage: tab.systemImage,
                        isSelected: drawer.openTab == tab
                    ) {
                        drawer.toggle(tab)
                    }
                }
            }
            .padding(6)
            .dwGlass(radius: DWRadius.xxl)

            Button(action: saveToPhotos) {
                VStack(spacing: DWSpace.xs) {
                    Image(systemName: savedToPhotos ? "checkmark" : "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                    Text("canvas.save")
                        .font(DWFont.ui(9.5, .semibold))
                }
                .foregroundStyle(DWColor.ground)
                .frame(width: 62, height: 64)
                .background(DWColor.text, in: RoundedRectangle(cornerRadius: DWRadius.xxl, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(stereogramVM.resultImage == nil)
            .accessibilityLabel(savedToPhotos ? "result.saved_to_photos" : "result.save_to_photos")
        }
    }

    // MARK: - Data

    private var depthTitle: String {
        guard let depthMap else { return String(localized: "depth.section_title") }
        return switch depthMap.source {
        case .lidar: "LiDAR"
        case .imported: String(localized: "depth.source_imported")
        case .model3D: String(localized: "depth.source_3d_model")
        case .depthAnything: String(localized: "depth.source_ai")
        }
    }

    private var depthSubtitle: String? {
        guard let depthMap else { return nil }
        return String(localized: "canvas.depth_subtitle \(depthMap.width) \(depthMap.height)")
    }

    // MARK: - Actions

    private func saveToPhotos() {
        guard let image = stereogramVM.resultImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        withAnimation(.snappy) { savedToPhotos = true }
    }

    private func triggerGeneration() {
        guard let depthMap else {
            stereogramVM.resultImage = nil
            return
        }
        savedToPhotos = false
        stereogramVM.generateDebounced(depthMap: depthMap, settings: settings)
    }

    private func updatePatternPreview() {
        if case .procedural = settings.patternSource {
            patternPreviewVM.updatePreview(source: settings.patternSource)
        }
    }
}
#endif
