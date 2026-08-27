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
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var chromeVisible = true
    @AppStorage("canvas.hintDismissed") private var hintDismissed = false
    @AppStorage("trainer.hasSeen") private var trainerSeen = false
    @StateObject private var stereogramVM = StereogramViewModel()
    @StateObject private var patternPreviewVM = PatternPreviewViewModel()

    private let drawerAnimation = Animation.spring(response: 0.38, dampingFraction: 0.86)

    var body: some View {
        ZStack(alignment: .bottom) {
            canvas
            floatingChrome
                .opacity(chromeVisible ? 1 : 0)
                .allowsHitTesting(chromeVisible)
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
        .statusBarHidden(!chromeVisible)
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
                        // This frame *is* zoom 1 — the full-bleed, cropped
                        // framing. Nothing clips here: the clip belongs to the
                        // container, so pinching back out reveals the cropped
                        // edges instead of empty ground.
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(zoom)
                        .offset(offset)
                        .accessibilityLabel("result.preview")
                        .accessibilityHint("canvas.zoom_accessibility_hint")
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
                        // Its background covers the canvas, so left hit-testable
                        // it swallows every gesture during a re-render.
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                zoomAndPan(container: proxy.size),
                including: canvasGesturesEnabled ? .all : .subviews
            )
            .onTapGesture(count: 2) { handleDoubleTap() }
            .onTapGesture { handleSingleTap() }
            .onChange(of: stereogramVM.resultImage) { old, new in
                reconcileZoom(old: old, new: new, container: proxy.size)
            }
            .onChange(of: proxy.size) { _, size in
                clampZoomAndOffset(container: size)
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
                    DWHintPill(text: "canvas.pinch_hint")
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

            // Secondary before primary, and narrower, so the pair reads as one
            // block and the chips keep enough room for the French labels.
            HStack(spacing: DWSpace.xs) {
                shareTile
                saveTile
            }
        }
    }

    private var saveTile: some View {
        Button(action: saveToPhotos) {
            actionTile(
                systemImage: savedToPhotos ? "checkmark" : "square.and.arrow.down",
                title: "canvas.save",
                width: 62
            )
            .foregroundStyle(DWColor.ground)
            .background(DWColor.text, in: RoundedRectangle(cornerRadius: DWRadius.xxl, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(stereogramVM.resultImage == nil)
        .accessibilityLabel(savedToPhotos ? "result.saved_to_photos" : "result.save_to_photos")
    }

    /// `ShareLink` needs a non-optional item, so the empty state is a dimmed
    /// stand-in of the same size rather than nothing — letting the tile appear
    /// with the first render would shove the chips sideways.
    @ViewBuilder
    private var shareTile: some View {
        let label = actionTile(systemImage: "square.and.arrow.up", title: "canvas.share", width: 52)
            .foregroundStyle(DWColor.text)

        if let image = stereogramVM.resultImage {
            ShareLink(
                item: Image(platformImage: image),
                preview: SharePreview(
                    String(localized: "result.title"),
                    image: Image(platformImage: image)
                )
            ) {
                label.dwGlass(radius: DWRadius.xxl)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("result.share")
        } else {
            label
                .dwGlass(radius: DWRadius.xxl)
                .opacity(0.4)
                .accessibilityHidden(true)
        }
    }

    private func actionTile(systemImage: String, title: LocalizedStringKey, width: CGFloat) -> some View {
        VStack(spacing: DWSpace.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .contentTransition(.symbolEffect(.replace))
            Text(title)
                .font(DWFont.ui(9.5, .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(width: width, height: 64)
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

    // MARK: - Zoom geometry

    private static let maxZoom: CGFloat = 3

    /// Pinch and pan belong to the image; while the drawer is up it owns the
    /// screen (and runs its own drag-to-dismiss), so the canvas lets go.
    private var canvasGesturesEnabled: Bool {
        !drawer.isOpen && stereogramVM.resultImage != nil
    }

    /// The factor `.scaledToFill()` applies to this image in this container.
    private func fillScale(_ image: PlatformImage, _ container: CGSize) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0 else { return 1 }
        return max(container.width / image.size.width, container.height / image.size.height)
    }

    /// The zoom at which the whole image fits on screen — the floor of the zoom
    /// range, and always ≤ 1, since 1 is the cropped full-bleed framing.
    private func fitRatio(_ image: PlatformImage, _ container: CGSize) -> CGFloat {
        guard image.size.width > 0, image.size.height > 0,
              container.width > 0, container.height > 0 else { return 1 }
        let fit = min(container.width / image.size.width, container.height / image.size.height)
        return fit / fillScale(image, container)
    }

    /// Holds the image's edges inside the container, and re-centres it on an
    /// axis where it no longer covers.
    private func clampOffset(
        _ raw: CGSize,
        image: PlatformImage,
        container: CGSize,
        zoom: CGFloat
    ) -> CGSize {
        guard image.size.width > 0, image.size.height > 0 else { return .zero }
        let scale = fillScale(image, container) * zoom
        let maxX = max(0, (image.size.width * scale - container.width) / 2)
        let maxY = max(0, (image.size.height * scale - container.height) / 2)
        return CGSize(
            width: min(max(raw.width, -maxX), maxX),
            height: min(max(raw.height, -maxY), maxY)
        )
    }

    private func zoomAndPan(container: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard let image = stereogramVM.resultImage else { return }
                zoom = min(
                    max(lastZoom * value.magnification, fitRatio(image, container)),
                    Self.maxZoom
                )
                offset = clampOffset(offset, image: image, container: container, zoom: zoom)
                if !hintDismissed { hintDismissed = true }
            }
            .onEnded { _ in
                lastZoom = zoom
                lastOffset = offset
            }
            // Panning matters at zoom 1 too: the resting framing already crops.
            .simultaneously(with:
                DragGesture()
                    .onChanged { value in
                        guard let image = stereogramVM.resultImage else { return }
                        let raw = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                        offset = clampOffset(raw, image: image, container: container, zoom: zoom)
                    }
                    .onEnded { _ in lastOffset = offset }
            )
    }

    private func handleSingleTap() {
        if drawer.isOpen {
            drawer = .closed
            return
        }
        guard stereogramVM.resultImage != nil else { return }
        if !hintDismissed { hintDismissed = true }
        withAnimation(.smooth(duration: 0.25)) { chromeVisible.toggle() }
    }

    private func handleDoubleTap() {
        guard canvasGesturesEnabled else { return }
        withAnimation(.smooth(duration: 0.3)) {
            zoom = zoom == 1 ? Self.maxZoom : 1
            offset = .zero
            lastZoom = zoom
            lastOffset = offset
        }
    }

    /// A new render lands on every slider tick, and pulling the user out of a
    /// zoomed inspection mid-drag is exactly the wrong moment — so the zoom
    /// survives a re-render of the same shape, and only resets when the aspect
    /// ratio changes under it.
    private func reconcileZoom(old: PlatformImage?, new: PlatformImage?, container: CGSize) {
        guard let new, new.size.width > 0, new.size.height > 0 else {
            resetZoom(animated: false)
            return
        }
        let oldAspect: CGFloat? = {
            guard let old, old.size.height > 0 else { return nil }
            return old.size.width / old.size.height
        }()
        if let oldAspect, abs(oldAspect - new.size.width / new.size.height) < 0.001 {
            clampZoomAndOffset(container: container)
        } else {
            resetZoom(animated: old != nil)
        }
    }

    private func clampZoomAndOffset(container: CGSize) {
        guard let image = stereogramVM.resultImage else { return }
        zoom = min(max(zoom, fitRatio(image, container)), Self.maxZoom)
        lastZoom = zoom
        offset = clampOffset(offset, image: image, container: container, zoom: zoom)
        lastOffset = offset
    }

    private func resetZoom(animated: Bool) {
        let apply = {
            zoom = 1
            lastZoom = 1
            offset = .zero
            lastOffset = .zero
        }
        if animated {
            withAnimation(.smooth(duration: 0.3), apply)
        } else {
            apply()
        }
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
