#if os(iOS)
import PhotosUI
import SwiftUI

/// Drawer tab for the repeating pattern the stereogram is woven from.
///
/// Same two strips as before — bundled textures and procedural generators —
/// restyled onto the design system, with `ProceduralParamsView` (shared with
/// macOS) embedded unchanged when a generator is selected.
struct PatternToolView: View {
    @Binding var settings: StereogramSettings
    @Binding var selectedPatternPhoto: PhotosPickerItem?
    @ObservedObject var patternPreviewVM: PatternPreviewViewModel

    private let tile: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: DWSpace.l) {
            VStack(alignment: .leading, spacing: DWSpace.s) {
                DWSectionLabel("pattern.textures_section")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DWSpace.m) {
                        ForEach(StereogramPattern.allCases) { pattern in
                            let source = PatternSource.asset(pattern)
                            patternTile(
                                isSelected: settings.patternSource == source,
                                caption: pattern.displayName
                            ) {
                                Image(uiImage: pattern.loadImage())
                                    .resizable()
                                    .interpolation(.none)
                            } action: {
                                settings.patternSource = source
                            }
                            .accessibilityLabel(pattern.displayName)
                            .accessibilityAddTraits(settings.patternSource == source ? .isSelected : [])
                        }

                        PhotosPicker(selection: $selectedPatternPhoto, matching: .images) {
                            tileBody(
                                isSelected: settings.patternSource.id == "imported",
                                caption: String(localized: "pattern.import", comment: "Pattern name")
                            ) {
                                if case .imported(let image) = settings.patternSource {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                } else {
                                    placeholder(icon: "photo.badge.plus")
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "pattern.import_accessibility", comment: "Accessibility label"))
                    }
                    .padding(.vertical, 2)
                }
            }

            VStack(alignment: .leading, spacing: DWSpace.s) {
                DWSectionLabel("pattern.generated_section")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DWSpace.m) {
                        ForEach(ProceduralPatternType.allCases) { type in
                            let isSelected = isProceduralSelected(type)
                            patternTile(isSelected: isSelected, caption: type.displayName) {
                                if let preview = patternPreviewVM.previewImage, isSelected {
                                    Image(uiImage: preview)
                                        .resizable()
                                        .interpolation(.none)
                                } else {
                                    placeholder(icon: type.iconSystemName)
                                }
                            } action: {
                                selectProceduralType(type)
                            }
                            .accessibilityLabel(type.displayName)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 2)
                }

                if case .procedural(let type, let config) = settings.patternSource {
                    ProceduralParamsView(
                        type: type,
                        config: Binding(
                            get: { config },
                            set: { settings.patternSource = .procedural(type, $0) }
                        ),
                        previewImage: patternPreviewVM.previewImage,
                        isGenerating: patternPreviewVM.isGenerating
                    )
                    .padding(.top, DWSpace.xs)
                }
            }
        }
    }

    // MARK: - Tiles

    private func patternTile<Content: View>(
        isSelected: Bool,
        caption: String,
        @ViewBuilder content: () -> Content,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            tileBody(isSelected: isSelected, caption: caption, content: content)
        }
        .buttonStyle(.plain)
    }

    private func tileBody<Content: View>(
        isSelected: Bool,
        caption: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: DWSpace.xs) {
            content()
                .frame(width: tile, height: tile)
                .clipShape(RoundedRectangle(cornerRadius: DWRadius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DWRadius.md, style: .continuous)
                        .strokeBorder(isSelected ? DWColor.cyan : .clear, lineWidth: 2)
                        .animation(.snappy(duration: 0.2), value: isSelected)
                )

            Text(caption)
                .font(DWFont.ui(10))
                .foregroundStyle(isSelected ? DWColor.cyan : DWColor.textSecondary)
                .lineLimit(1)
        }
        .frame(width: tile)
    }

    private func placeholder(icon: String) -> some View {
        Image(systemName: icon)
            .font(.system(size: 20))
            .foregroundStyle(DWColor.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DWColor.glassFillRaised)
    }

    // MARK: - Selection

    private func isProceduralSelected(_ type: ProceduralPatternType) -> Bool {
        if case .procedural(let selectedType, _) = settings.patternSource {
            return selectedType == type
        }
        return false
    }

    private func selectProceduralType(_ type: ProceduralPatternType) {
        if case .procedural(let currentType, let config) = settings.patternSource,
           currentType == type {
            // Already selected, keep current config
            settings.patternSource = .procedural(type, config)
        } else {
            settings.patternSource = .procedural(type, type.defaultConfig())
        }
    }
}
#endif
