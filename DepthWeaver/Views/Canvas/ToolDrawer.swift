#if os(iOS)
import PhotosUI
import SwiftUI

/// The glass drawer the floating bar expands into.
///
/// Deliberately a plain overlay rather than a `.sheet`: it has to host the very
/// same chip row that was just in the bar, so opening reads as the bar growing
/// rather than a new surface arriving, and the canvas has to stay visible and
/// tappable behind it.
struct ToolDrawer: View {
    @Binding var drawer: DrawerState
    @Binding var depthMap: DepthMap?
    @Binding var settings: StereogramSettings
    @Binding var path: NavigationPath
    @Binding var selectedPatternPhoto: PhotosPickerItem?
    @ObservedObject var patternPreviewVM: PatternPreviewViewModel
    let resultImage: PlatformImage?
    @Binding var savedToPhotos: Bool
    let onSave: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            // A ScrollView's ideal height is unbounded, so left alone it would
            // stretch the drawer to its cap even for the short Depth tab.
            // Measure the content and let the drawer hug it up to that cap.
            let maxContent = proxy.size.height * 0.72 - 190

            VStack(spacing: DWSpace.l) {
                grabHandle
                chipRow

                ScrollView {
                    tabContent
                        .padding(.bottom, DWSpace.s)
                        .background {
                            GeometryReader { inner in
                                Color.clear.preference(
                                    key: DrawerContentHeightKey.self,
                                    value: inner.size.height
                                )
                            }
                        }
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: min(max(contentHeight, 1), max(maxContent, 1)))
                .onPreferenceChange(DrawerContentHeightKey.self) { contentHeight = $0 }

                saveRow
            }
            .padding(.horizontal, DWSpace.l)
            .padding(.top, DWSpace.m)
            .padding(.bottom, DWSpace.section)
            .frame(maxWidth: .infinity)
            .background {
                UnevenRoundedRectangle(
                    topLeadingRadius: DWRadius.hero,
                    topTrailingRadius: DWRadius.hero,
                    style: .continuous
                )
                .fill(.ultraThinMaterial)
                .overlay {
                    UnevenRoundedRectangle(
                        topLeadingRadius: DWRadius.hero,
                        topTrailingRadius: DWRadius.hero,
                        style: .continuous
                    )
                    .fill(DWColor.surface.opacity(0.86))
                }
                .overlay(alignment: .top) {
                    Rectangle().fill(DWColor.hairline).frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            // The drawer runs to the bottom edge and hosts custom drag controls
            // (sliders, the grab handle), so the home-indicator swipe would
            // otherwise steal their first gesture.
            .defersSystemGestures(on: .bottom)
            .offset(y: dragOffset)
            .gesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        dragOffset = max(0, value.translation.height)
                    }
                    .onEnded { value in
                        let shouldClose = value.translation.height > proxy.size.height * 0.15
                            || value.predictedEndTranslation.height > 240
                        dragOffset = 0
                        if shouldClose { drawer = .closed }
                    }
            )
        }
    }

    private struct DrawerContentHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    private var grabHandle: some View {
        Capsule()
            .fill(DWColor.hairlineStrong)
            .frame(width: 38, height: 4)
            .accessibilityLabel("canvas.drawer_handle_accessibility")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { drawer = .closed }
    }

    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(ToolTab.allCases) { tab in
                DWToolChip(
                    title: LocalizedStringKey(String(localized: tab.title)),
                    systemImage: tab.systemImage,
                    isSelected: drawer.openTab == tab,
                    showsIcon: false
                ) {
                    drawer.toggle(tab)
                }
                .dwGlass(radius: DWRadius.md)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch drawer.openTab {
        case .depth:
            DepthToolView(depthMap: $depthMap, path: $path)
        case .pattern:
            PatternToolView(
                settings: $settings,
                selectedPatternPhoto: $selectedPatternPhoto,
                patternPreviewVM: patternPreviewVM
            )
        case .tune:
            TuneToolView(settings: $settings, depthMap: $depthMap, path: $path)
        case nil:
            EmptyView()
        }
    }

    private var saveRow: some View {
        HStack(spacing: DWSpace.s) {
            Button(action: onSave) {
                Label(
                    savedToPhotos ? "result.saved_to_photos" : "canvas.save_to_photos",
                    systemImage: savedToPhotos ? "checkmark" : "square.and.arrow.down"
                )
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(DWWhiteButtonStyle())
            .disabled(resultImage == nil)

            if let resultImage {
                ShareLink(
                    item: Image(platformImage: resultImage),
                    preview: SharePreview(
                        String(localized: "result.title"),
                        image: Image(platformImage: resultImage)
                    )
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(DWColor.text)
                        .frame(width: DWMetric.primaryButton, height: DWMetric.primaryButton)
                        .dwGlass(radius: DWRadius.xl)
                }
                .accessibilityLabel("result.share")
            }
        }
    }
}
#endif
