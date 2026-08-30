#if os(iOS)
import PhotosUI
import SceneKit
import SwiftUI

/// The main screen: the stereogram *is* the interface.
///
/// Everything that used to sit above the result in a scrolling stack now floats
/// over it — an info pill, a help button, and a bar whose three chips expand
/// into ``ToolDrawer``.
///
/// The canvas answers gestures in one of two ways, picked with the toggle in
/// the top bar. In ``CanvasMode/view`` they move the finished image, the way
/// they always have. In ``CanvasMode/live`` they reach past it and move the
/// *source*: a flat depth map pans and zooms, a 3D model turns, slides and
/// dollies, and the stereogram is regenerated for every frame of the gesture.
struct CanvasScreen: View {
    @Binding var depthMap: DepthMap?
    @Binding var path: NavigationPath
    /// The model behind a `.model3D` depth map, when one is loaded. Live mode
    /// orbits it instead of panning the captured depth.
    var scene3D: SCNScene?

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
    @State private var mode: CanvasMode = .view
    @State private var canvasSize: CGSize = .zero
    @State private var liveHintVisible = false
    /// Rendering the hue ramp is per-pixel work, so the swatch is computed when
    /// the depth changes rather than on every pass of the body — live mode
    /// re-evaluates it dozens of times a second.
    @State private var depthThumbnail: PlatformImage?
    @StateObject private var liveScene = LiveSceneViewModel()
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
            liveScene.attach(scene: scene3D)
            refreshDepthThumbnail()
            triggerGeneration()
            // Nobody opens a help sheet before they have failed once; offer the
            // trainer up front instead, exactly once.
            if !trainerSeen {
                trainerSeen = true
                showHelp = true
            }
        }
        .onChange(of: depthMap?.id) { _, _ in
            refreshDepthThumbnail()
            triggerGeneration()
        }
        .onChange(of: scene3D.map { ObjectIdentifier($0) }) { _, _ in
            liveScene.attach(scene: scene3D)
        }
        .onChange(of: mode) { _, newMode in
            enter(mode: newMode)
        }
        .onChange(of: depthMap?.adjustment) { _, _ in
            refreshDepthThumbnail()
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

                // Live mode never shows the spinner: it re-renders on every
                // frame of a gesture, and a veil blinking in and out under the
                // finger is worse than a slightly stale image.
                if (stereogramVM.isGenerating && mode == .view) || stereogramVM.resultImage == nil {
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
            // Live mode needs a one-finger drag told apart from a two-finger
            // one, which only UIKit can do — so it brings its own recognizers
            // and takes over every tap while it is up.
            .overlay {
                if mode == .live {
                    LiveGestureView(
                        onPan: { translation, touches, phase in
                            handleLivePan(
                                translation,
                                touches: touches,
                                phase: phase,
                                container: proxy.size
                            )
                        },
                        onPinch: { factor, phase in
                            handleLivePinch(factor, phase: phase, container: proxy.size)
                        },
                        onTap: handleSingleTap,
                        onDoubleTap: handleDoubleTap
                    )
                    .allowsHitTesting(liveGesturesEnabled)
                }
            }
            .onAppear { canvasSize = proxy.size }
            .onChange(of: stereogramVM.resultImage) { old, new in
                reconcileZoom(old: old, new: new, container: proxy.size)
            }
            .onChange(of: proxy.size) { _, size in
                canvasSize = size
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
                if let hint = activeHint {
                    DWHintPill(text: hint)
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
        // Tighter than the rest of the chrome: the depth pill, the reset
        // affordance, the mode toggle and the help button all share one row,
        // and the pill is the one that has to keep its label readable.
        HStack(alignment: .top, spacing: DWSpace.s) {
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

            if mode == .live && liveFramingMoved {
                Button(action: resetLiveFraming) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(DWCircleGlassButtonStyle(size: 34))
                .accessibilityLabel("canvas.reset_framing")
                .transition(.opacity.combined(with: .scale))
            }

            modeToggle

            Button { showHelp = true } label: {
                Image(systemName: "questionmark")
            }
            .buttonStyle(DWCircleGlassButtonStyle())
            .accessibilityLabel("trainer.header")
        }
        .animation(.smooth(duration: 0.2), value: liveFramingMoved)
    }

    /// Two icons rather than two words: the French labels for "image" and
    /// "live" don't fit next to the depth pill on a small phone, and the hint
    /// pill below spells out what the active mode does anyway.
    private var modeToggle: some View {
        HStack(spacing: 2) {
            ForEach(CanvasMode.allCases) { candidate in
                Button {
                    guard mode != candidate else { return }
                    withAnimation(.smooth(duration: 0.2)) { mode = candidate }
                } label: {
                    Image(systemName: candidate.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(mode == candidate ? DWColor.ground : DWColor.textSecondary)
                        .frame(width: 38, height: 32)
                        .background {
                            RoundedRectangle(cornerRadius: DWRadius.sm, style: .continuous)
                                .fill(mode == candidate ? DWColor.text : .clear)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: DWRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(candidate == .live && depthMap == nil)
                .accessibilityLabel(LocalizedStringKey(String(localized: candidate.title)))
                .accessibilityAddTraits(mode == candidate ? [.isSelected] : [])
            }
        }
        .padding(3)
        .dwGlass(radius: DWRadius.md)
    }

    @ViewBuilder
    private var depthSwatch: some View {
        if let preview = depthThumbnail {
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
    /// screen (and runs its own drag-to-dismiss), so the canvas lets go — and
    /// live mode takes them over entirely.
    private var canvasGesturesEnabled: Bool {
        mode == .view && !drawer.isOpen && stereogramVM.resultImage != nil
    }

    private var liveGesturesEnabled: Bool {
        mode == .live && !drawer.isOpen && depthMap != nil
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
        if mode == .live {
            resetLiveFraming()
            return
        }
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

    // MARK: - Live mode

    /// True when a gesture should orbit a model rather than pan a flat map: the
    /// depth on screen has to *come from* the loaded scene, otherwise turning
    /// the model would have nothing to do with what is rendered.
    private var isLive3D: Bool {
        liveScene.hasScene && depthMap?.source == .model3D
    }

    private var liveFramingMoved: Bool {
        if isLive3D { return !liveScene.isHome }
        return !(depthMap?.transform.isIdentity ?? true)
    }

    private var activeHint: LocalizedStringKey? {
        guard stereogramVM.resultImage != nil else { return nil }
        if mode == .live {
            guard liveHintVisible else { return nil }
            return isLive3D ? "canvas.live_hint_model" : "canvas.live_hint_flat"
        }
        return hintDismissed ? nil : "canvas.pinch_hint"
    }

    /// Depth resolution captured per live frame. Derived from the container, so
    /// the aspect ratio — and with it the framing of the result on screen —
    /// stays put from one capture to the next.
    private static let liveCaptureMinDimension: CGFloat = 384

    private func liveCaptureSize(container: CGSize) -> CGSize {
        let side = min(container.width, container.height)
        guard side > 0 else {
            return CGSize(
                width: Self.liveCaptureMinDimension,
                height: Self.liveCaptureMinDimension
            )
        }
        let scale = Self.liveCaptureMinDimension / side
        return CGSize(
            width: max(1, (container.width * scale).rounded()),
            height: max(1, (container.height * scale).rounded())
        )
    }

    /// On-screen size of the result at zoom 1 — the denominator that turns a
    /// finger's travel into a fraction of the depth map.
    private func displayedImageSize(container: CGSize) -> CGSize {
        guard let image = stereogramVM.resultImage,
              image.size.width > 0, image.size.height > 0
        else { return container }
        let scale = fillScale(image, container)
        return CGSize(width: image.size.width * scale, height: image.size.height * scale)
    }

    private func enter(mode newMode: CanvasMode) {
        stereogramVM.cancelLive()
        guard newMode == .live else {
            liveHintVisible = false
            // Back to inspecting: re-render whatever framing live mode left, at
            // full quality this time.
            triggerGeneration()
            return
        }
        liveHintVisible = true
        resetZoom(animated: true)
        // A model is driven by its own camera, so live mode opens by capturing
        // from that camera rather than keeping the still the capture screen
        // happened to save.
        guard isLive3D, let base = depthMap,
              let captured = liveScene.captureDepth(size: liveCaptureSize(container: canvasSize))
        else {
            triggerGeneration()
            return
        }
        var next = captured
        next.adoptRemap(from: base.adjustment)
        depthMap = next
    }

    private func handleLivePan(
        _ translation: CGSize,
        touches: Int,
        phase: LiveGesturePhase,
        container: CGSize
    ) {
        guard liveGesturesEnabled else { return }
        if liveHintVisible { liveHintVisible = false }
        if isLive3D {
            if touches >= 2 {
                liveScene.pan(dx: translation.width, dy: translation.height, viewHeight: container.height)
            } else {
                liveScene.rotate(dx: translation.width, dy: translation.height)
            }
        } else {
            let displayed = displayedImageSize(container: container)
            guard displayed.width > 0, displayed.height > 0 else { return }
            depthMap?.transform.pan(
                dx: Float(translation.width / displayed.width),
                dy: Float(translation.height / displayed.height)
            )
        }
        renderLive(phase: phase, container: container)
    }

    private func handleLivePinch(_ factor: CGFloat, phase: LiveGesturePhase, container: CGSize) {
        guard liveGesturesEnabled else { return }
        if liveHintVisible { liveHintVisible = false }
        if isLive3D {
            liveScene.zoom(by: factor)
        } else {
            depthMap?.transform.zoom(by: Float(factor))
        }
        renderLive(phase: phase, container: container)
    }

    private func resetLiveFraming() {
        guard mode == .live, liveFramingMoved else { return }
        if isLive3D {
            liveScene.reset()
        } else {
            depthMap?.transform = .identity
        }
        renderLive(phase: .ended, container: canvasSize)
    }

    /// Renders the framing a gesture just produced: coarse and coalesced while
    /// the finger is down, full quality the moment it lifts.
    private func renderLive(phase: LiveGesturePhase, container: CGSize) {
        guard let base = depthMap else { return }
        guard isLive3D else {
            if phase == .ended {
                refreshDepthThumbnail()
                triggerGeneration()
            } else {
                stereogramVM.generateLive(depthMap: base, settings: settings)
            }
            return
        }
        // Re-rendering the scene into a depth buffer costs more than the touch
        // stream can afford, so mid-gesture frames are captured only when the
        // generator is ready for one — the final frame always is.
        guard phase == .ended || !stereogramVM.hasPendingLiveFrame else { return }
        guard let captured = liveScene.captureDepth(size: liveCaptureSize(container: container)) else { return }
        var next = captured
        next.adoptRemap(from: base.adjustment)
        if phase == .ended {
            // Committing swaps the map's identity, and that is what schedules
            // the full-quality render; the drawer and the depth pill pick the
            // new capture up in the same pass.
            depthMap = next
        } else {
            stereogramVM.generateLive(depthMap: next, settings: settings)
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

    private func refreshDepthThumbnail() {
        depthThumbnail = depthMap?.previewImage(maxDimension: 96)
    }

    private func updatePatternPreview() {
        if case .procedural = settings.patternSource {
            patternPreviewVM.updatePreview(source: settings.patternSource)
        }
    }
}
#endif
